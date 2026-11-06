/* eslint-disable @typescript-eslint/no-unsafe-argument, @typescript-eslint/no-unsafe-assignment, @typescript-eslint/no-unsafe-call, @typescript-eslint/no-unsafe-member-access -- ExcelJS exposes worksheet cell values through untyped CommonJS APIs; all values are normalised and validated below. */
import ExcelJS from 'exceljs';
import { extname } from 'node:path';
import type { PoolClient } from 'pg';

export const hierarchyColumns = ['type', 'name', 'code', 'parent_code', 'is_active'] as const;
export type HierarchyColumn = (typeof hierarchyColumns)[number];
export type ImportedOrgUnitType = 'COUNTRY' | 'REGION' | 'PROVINCE' | 'ZONE' | 'AREA' | 'PARISH';

export interface HierarchyImportRow {
  type: ImportedOrgUnitType;
  name: string;
  code: string;
  parentCode?: string;
  isActive: boolean;
}

interface ExistingUnit {
  id: string;
  type: ImportedOrgUnitType;
  parent_id: string | null;
}

const expectedParent: Partial<Record<ImportedOrgUnitType, ImportedOrgUnitType>> = {
  REGION: 'COUNTRY',
  PROVINCE: 'REGION',
  ZONE: 'PROVINCE',
  AREA: 'ZONE',
  PARISH: 'AREA',
};

function cellText(value: unknown): string {
  if (value === null || value === undefined) {
    return '';
  }
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  if (value instanceof Date) {
    return value.toISOString();
  }
  return '';
}

function required(value: unknown, column: string, rowNumber: number): string {
  const normalized = cellText(value).trim();
  if (!normalized) {
    throw new Error(`Row ${rowNumber}: ${column} is required.`);
  }
  return normalized;
}

function optional(value: unknown): string | undefined {
  const normalized = cellText(value).trim();
  return normalized || undefined;
}

function parseActive(value: unknown, rowNumber: number): boolean {
  const normalized = cellText(value).trim().toLowerCase() || 'true';
  if (['true', '1', 'yes', 'active'].includes(normalized)) {
    return true;
  }
  if (['false', '0', 'no', 'inactive'].includes(normalized)) {
    return false;
  }
  throw new Error(`Row ${rowNumber}: is_active must be true or false.`);
}

export function normalizeHierarchyRows(records: Record<string, unknown>[]): HierarchyImportRow[] {
  const seenCodes = new Set<string>();
  return records.map((record, index) => {
    const rowNumber = index + 2;
    const type = required(record.type, 'type', rowNumber).toUpperCase() as ImportedOrgUnitType;
    if (!['COUNTRY', 'REGION', 'PROVINCE', 'ZONE', 'AREA', 'PARISH'].includes(type)) {
      throw new Error(`Row ${rowNumber}: unsupported type ${type}.`);
    }
    const code = required(record.code, 'code', rowNumber).toUpperCase();
    if (seenCodes.has(code)) {
      throw new Error(`Row ${rowNumber}: duplicate code ${code}.`);
    }
    seenCodes.add(code);
    const parentCode = optional(record.parent_code)?.toUpperCase();
    if (type === 'COUNTRY' && parentCode) {
      throw new Error(`Row ${rowNumber}: COUNTRY must not have parent_code.`);
    }
    if (type !== 'COUNTRY' && !parentCode) {
      throw new Error(`Row ${rowNumber}: ${type} requires parent_code.`);
    }
    return {
      type,
      name: required(record.name, 'name', rowNumber),
      code,
      parentCode,
      isActive: parseActive(record.is_active, rowNumber),
    };
  });
}

export async function readHierarchyFile(filename: string): Promise<HierarchyImportRow[]> {
  const extension = extname(filename).toLowerCase();
  if (!['.csv', '.xlsx', '.xlsm'].includes(extension)) {
    throw new Error('Hierarchy import must be a .csv, .xlsx, or .xlsm file.');
  }
  const workbook = new ExcelJS.Workbook();
  if (extension === '.csv') {
    await workbook.csv.readFile(filename);
  } else {
    await workbook.xlsx.readFile(filename);
  }
  const sheet = workbook.worksheets[0];
  if (!sheet) {
    throw new Error('Hierarchy import workbook has no worksheet.');
  }
  const firstRowValues = sheet.getRow(1).values as ExcelJS.CellValue[];
  const headings: string[] = firstRowValues
    .slice(1)
    .map((value: ExcelJS.CellValue) => cellText(value).trim().toLowerCase());
  for (const column of hierarchyColumns) {
    if (!headings.includes(column)) {
      throw new Error(`Hierarchy import is missing required column: ${column}.`);
    }
  }
  const records: Record<string, unknown>[] = [];
  sheet.eachRow((row, rowNumber) => {
    const rowValues = row.values as ExcelJS.CellValue[];
    if (
      rowNumber === 1 ||
      rowValues.slice(1).every((value: ExcelJS.CellValue) => cellText(value).trim() === '')
    ) {
      return;
    }
    const record: Record<string, unknown> = {};
    headings.forEach((heading: string, index: number) => {
      record[heading] = row.getCell(index + 1).text;
    });
    records.push(record);
  });
  return normalizeHierarchyRows(records);
}

export function sortHierarchyRows(rows: HierarchyImportRow[]): HierarchyImportRow[] {
  const pending = new Map(rows.map((row) => [row.code, row]));
  const ordered: HierarchyImportRow[] = [];
  while (pending.size > 0) {
    let progressed = false;
    for (const [code, row] of pending) {
      if (
        !row.parentCode ||
        !pending.has(row.parentCode) ||
        ordered.some((item) => item.code === row.parentCode)
      ) {
        const parent = row.parentCode
          ? rows.find((item) => item.code === row.parentCode)
          : undefined;
        if (parent && parent.type !== expectedParent[row.type]) {
          throw new Error(`Unit ${row.code} has invalid ${parent.type} parent ${parent.code}.`);
        }
        ordered.push(row);
        pending.delete(code);
        progressed = true;
      }
    }
    if (!progressed) {
      const unresolved = [...pending.values()]
        .map((row) => `${row.code} -> ${row.parentCode}`)
        .join(', ');
      throw new Error(`Hierarchy has a cycle or missing parent reference: ${unresolved}`);
    }
  }
  return ordered;
}

export async function applyHierarchyImport(
  client: PoolClient,
  inputRows: HierarchyImportRow[],
): Promise<{ created: number; updated: number; moved: number }> {
  const rows = sortHierarchyRows(inputRows);
  const knownByCodeResult = await client.query<ExistingUnit & { code: string }>(
    'SELECT id, type::text, parent_id, code FROM org_units',
  );
  const knownByCode = new Map(knownByCodeResult.rows.map((row) => [row.code, row]));
  let created = 0;
  let updated = 0;
  let moved = 0;

  for (const row of rows) {
    const parent = row.parentCode ? knownByCode.get(row.parentCode) : undefined;
    if (row.parentCode && !parent) {
      throw new Error(
        `Parent ${row.parentCode} for ${row.code} does not exist in the file or database.`,
      );
    }
    if (parent && parent.type !== expectedParent[row.type]) {
      throw new Error(`Unit ${row.code} cannot be placed under ${parent.type} ${row.parentCode}.`);
    }
    const current = knownByCode.get(row.code);
    if (!current) {
      const inserted = await client.query<ExistingUnit & { code: string }>(
        `INSERT INTO org_units (type, name, code, parent_id, is_active)
         VALUES ($1::org_unit_type, $2, $3, $4, $5)
         RETURNING id, type::text, parent_id, code`,
        [row.type, row.name, row.code, parent?.id ?? null, row.isActive],
      );
      knownByCode.set(row.code, inserted.rows[0]);
      created += 1;
      continue;
    }
    if (current.type !== row.type) {
      throw new Error(`Existing unit ${row.code} has type ${current.type}, not ${row.type}.`);
    }
    if ((current.parent_id ?? null) !== (parent?.id ?? null)) {
      if (!parent) {
        throw new Error(`Existing root ${row.code} cannot be moved without a parent.`);
      }
      await client.query('SELECT * FROM goye_move_org_unit($1, $2)', [current.id, parent.id]);
      moved += 1;
    }
    await client.query(`UPDATE org_units SET name = $1, is_active = $2 WHERE id = $3`, [
      row.name,
      row.isActive,
      current.id,
    ]);
    updated += 1;
  }
  return { created, updated, moved };
}
