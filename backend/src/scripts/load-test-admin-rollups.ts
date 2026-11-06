import { ConfigService } from '@nestjs/config';
import { performance } from 'node:perf_hooks';
import { pathToFileURL } from 'node:url';
import { Pool } from 'pg';
import { AdminReportsService } from '../admin/admin-reports.service.js';
import { AuditService } from '../audit/audit.service.js';
import type { AuthenticatedActor } from '../authorization/authorization.types.js';
import { DatabaseService } from '../database/database.service.js';
import { FieldEncryptionService } from '../privacy/field-encryption.service.js';
import { PrivacySettingsService } from '../privacy/privacy-settings.service.js';
import { requiredEnvironment } from './database-script.util.js';

const requiredConvertCount = 1_000_000;
interface Unit {
  id: string;
  path: string;
}

export interface TimingSummary {
  samples: number;
  minMilliseconds: number;
  p50Milliseconds: number;
  p95Milliseconds: number;
  maxMilliseconds: number;
}

export interface AdminRollupLoadTestResult {
  seededConverts: number;
  seedDurationMilliseconds: number;
  measuredAt: string;
  targetMilliseconds: number;
  allTargetsMet: boolean;
  totals: {
    grand: number;
    firstCountry: number;
    firstCountryRegions: number;
  };
  timings: Record<'countries' | 'regions' | 'countryTotal' | 'grandTotal', TimingSummary>;
}

export interface AdminRollupLoadTestOptions {
  connectionString: string;
  auditSecret: string;
  piiEncryptionKey: string;
  convertCount?: number;
  batchSize?: number;
  samples?: number;
  runLabel?: string;
  log?: (message: string) => void;
}

export async function runAdminRollupLoadTest(
  options: AdminRollupLoadTestOptions,
): Promise<AdminRollupLoadTestResult> {
  const convertCount = options.convertCount ?? requiredConvertCount;
  const batchSize = options.batchSize ?? 10_000;
  const samples = options.samples ?? 20;
  const runLabel = options.runLabel ?? `load${Date.now()}`;
  if (!Number.isSafeInteger(convertCount) || convertCount < 1) {
    throw new Error('convertCount must be a positive safe integer.');
  }
  if (!Number.isSafeInteger(batchSize) || batchSize < 1) {
    throw new Error('batchSize must be a positive safe integer.');
  }
  if (!Number.isSafeInteger(samples) || samples < 1) {
    throw new Error('samples must be a positive safe integer.');
  }
  if (!/^[a-z0-9]+$/.test(runLabel)) {
    throw new Error('runLabel must contain only lowercase letters and digits.');
  }

  const pool = new Pool({ connectionString: options.connectionString });
  let database: DatabaseService | undefined;
  try {
    const existing = await pool.query<{ count: string }>(
      'SELECT count(*)::text AS count FROM converts',
    );
    if (Number(existing.rows[0].count) > 0) {
      throw new Error(
        'Refusing to seed a database that already contains converts. Use an isolated load-test database.',
      );
    }

    const units = await seedHierarchy(pool, runLabel);
    const globalUser = await seedGlobalUser(pool, runLabel);
    const seedStarted = performance.now();
    await seedConverts(pool, {
      convertCount,
      batchSize,
      globalUserId: globalUser,
      parishIds: [
        units.get('ngparisha')!.id,
        units.get('ngparishb')!.id,
        units.get('ghparisha')!.id,
      ] as [string, string, string],
      log: options.log,
    });
    const seedDurationMilliseconds = performance.now() - seedStarted;

    const config = new ConfigService({
      DATABASE_URL: options.connectionString,
      AUDIT_CHAIN_SECRET: options.auditSecret,
      PII_ENCRYPTION_KEY: options.piiEncryptionKey,
    });
    database = new DatabaseService(config);
    const audit = new AuditService();
    const reports = new AdminReportsService(
      database,
      new FieldEncryptionService(config),
      config,
      audit,
      new PrivacySettingsService(database, audit, config),
    );
    const actor: AuthenticatedActor = {
      id: globalUser,
      sessionId: '00000000-0000-0000-0000-000000009999',
      roles: ['GLOBAL_ADMIN'],
      isGlobalAdmin: true,
    };
    const firstCountry = units.get('ng')!;

    const countries = await reports.listCountries(actor, {});
    const countryTotal = await reports.countryTotal(actor, firstCountry.id, {});
    const regions = await reports.listRegions(actor, firstCountry.id, {});
    const grand = await reports.grandTotal(actor, {});
    if (
      grand.total !== convertCount ||
      countries.reduce((total, country) => total + country.total, 0) !== convertCount
    ) {
      throw new Error('Seeded roll-up totals do not equal the requested convert count.');
    }

    const timings = {
      countries: await measure(samples, () => reports.listCountries(actor, {})),
      regions: await measure(samples, () => reports.listRegions(actor, firstCountry.id, {})),
      countryTotal: await measure(samples, () => reports.countryTotal(actor, firstCountry.id, {})),
      grandTotal: await measure(samples, () => reports.grandTotal(actor, {})),
    };
    const targetMilliseconds = 1_000;
    return {
      seededConverts: convertCount,
      seedDurationMilliseconds: round(seedDurationMilliseconds),
      measuredAt: new Date().toISOString(),
      targetMilliseconds,
      allTargetsMet: Object.values(timings).every(
        (timing) => timing.p95Milliseconds < targetMilliseconds,
      ),
      totals: {
        grand: grand.total,
        firstCountry: countryTotal.total,
        firstCountryRegions: regions.reduce((total, region) => total + region.total, 0),
      },
      timings,
    };
  } finally {
    await database?.onModuleDestroy();
    await pool.end();
  }
}

async function seedHierarchy(pool: Pool, label: string): Promise<Map<string, Unit>> {
  const units = new Map<string, Unit>();
  async function create(type: string, code: string, parentCode?: string): Promise<void> {
    const result = await pool.query<Unit>(
      `INSERT INTO org_units (type, name, code, parent_id)
       VALUES ($1::org_unit_type, $2, $3, $4) RETURNING id, path::text`,
      [
        type,
        `Load test ${code}`,
        code,
        parentCode ? units.get(parentCode.slice(label.length).toLowerCase())?.id : null,
      ],
    );
    units.set(code.slice(label.length).toLowerCase(), result.rows[0]);
  }

  await create('COUNTRY', `${label}ng`);
  await create('REGION', `${label}ngregion`, `${label}ng`);
  await create('PROVINCE', `${label}ngprovince`, `${label}ngregion`);
  await create('ZONE', `${label}ngzone`, `${label}ngprovince`);
  await create('AREA', `${label}ngarea`, `${label}ngzone`);
  await create('PARISH', `${label}ngparisha`, `${label}ngarea`);
  await create('PARISH', `${label}ngparishb`, `${label}ngarea`);
  await create('COUNTRY', `${label}gh`);
  await create('REGION', `${label}ghregion`, `${label}gh`);
  await create('PROVINCE', `${label}ghprovince`, `${label}ghregion`);
  await create('ZONE', `${label}ghzone`, `${label}ghprovince`);
  await create('AREA', `${label}gharea`, `${label}ghzone`);
  await create('PARISH', `${label}ghparisha`, `${label}gharea`);
  return units;
}

async function seedGlobalUser(pool: Pool, label: string): Promise<string> {
  const user = await pool.query<{ id: string }>(
    `INSERT INTO users (display_name, email_normalized, status)
     VALUES ($1, $2, 'ACTIVE') RETURNING id`,
    ['Load test Global Admin', `${label}.global.admin@load.test`],
  );
  await pool.query(
    `INSERT INTO user_roles (user_id, role_id, assigned_by)
     SELECT $1, id, $1 FROM roles WHERE key = 'GLOBAL_ADMIN'`,
    [user.rows[0].id],
  );
  return user.rows[0].id;
}

async function seedConverts(
  pool: Pool,
  options: {
    convertCount: number;
    batchSize: number;
    globalUserId: string;
    parishIds: [string, string, string];
    log?: (message: string) => void;
  },
): Promise<void> {
  for (let start = 1; start <= options.convertCount; start += options.batchSize) {
    const end = Math.min(start + options.batchSize - 1, options.convertCount);
    await pool.query(
      `INSERT INTO converts (
        full_name_encrypted, registered_at_unit_id, registered_by, parish_id,
        consent_granted, consent_version, consent_method, consent_captured_by, stage, created_at
      )
      SELECT
        decode(repeat('00', 30), 'hex'),
        CASE source.number % 3 WHEN 0 THEN $3::uuid WHEN 1 THEN $4::uuid ELSE $5::uuid END,
        $6::uuid,
        CASE source.number % 3 WHEN 0 THEN $3::uuid WHEN 1 THEN $4::uuid ELSE $5::uuid END,
        true,
        'load-test-v1',
        'DIGITAL'::consent_capture_method,
        $6::uuid,
        CASE source.number % 5
          WHEN 0 THEN 'NEW_CONVERT'::convert_stage
          WHEN 1 THEN 'BELIEVERS_CLASS'::convert_stage
          WHEN 2 THEN 'BAPTISMAL_CLASS'::convert_stage
          WHEN 3 THEN 'BAPTISED'::convert_stage
          ELSE 'FULLY_PLANTED'::convert_stage
        END,
        (CURRENT_DATE - ((source.number % 30)::integer))::timestamptz
      FROM generate_series($1::bigint, $2::bigint) AS source(number)`,
      [
        start,
        end,
        options.parishIds[0],
        options.parishIds[1],
        options.parishIds[2],
        options.globalUserId,
      ],
    );
    options.log?.(
      `Seeded ${end.toLocaleString()} / ${options.convertCount.toLocaleString()} converts`,
    );
  }
}

async function measure<T>(samples: number, operation: () => Promise<T>): Promise<TimingSummary> {
  for (let index = 0; index < 3; index += 1) {
    await operation();
  }
  const values: number[] = [];
  for (let index = 0; index < samples; index += 1) {
    const started = performance.now();
    await operation();
    values.push(performance.now() - started);
  }
  values.sort((left, right) => left - right);
  return {
    samples,
    minMilliseconds: round(values[0]),
    p50Milliseconds: percentile(values, 0.5),
    p95Milliseconds: percentile(values, 0.95),
    maxMilliseconds: round(values.at(-1)!),
  };
}

function percentile(values: number[], quantile: number): number {
  return round(values[Math.min(values.length - 1, Math.ceil(values.length * quantile) - 1)]);
}

function round(value: number): number {
  return Math.round(value * 100) / 100;
}

async function main(): Promise<void> {
  if (process.env.ALLOW_LOAD_TEST !== 'true') {
    throw new Error(
      'Set ALLOW_LOAD_TEST=true and use an isolated database to run this destructive load test.',
    );
  }
  const result = await runAdminRollupLoadTest({
    connectionString: requiredEnvironment('DATABASE_URL'),
    auditSecret: requiredEnvironment('AUDIT_CHAIN_SECRET'),
    piiEncryptionKey: requiredEnvironment('PII_ENCRYPTION_KEY'),
    convertCount: Number(process.env.LOAD_TEST_CONVERTS ?? requiredConvertCount),
    batchSize: Number(process.env.LOAD_TEST_BATCH_SIZE ?? 10_000),
    samples: Number(process.env.LOAD_TEST_SAMPLES ?? 20),
    runLabel: process.env.LOAD_TEST_LABEL ?? `load${Date.now()}`,
    log: (message) => console.log(message),
  });
  console.log(JSON.stringify(result, null, 2));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  void main();
}
