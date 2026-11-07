import Joi from 'joi';

export const environmentValidationSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'test', 'production').default('development'),
  PORT: Joi.number().port().default(3000),
  API_PREFIX: Joi.string()
    .pattern(/^api\/v\d+$/)
    .default('api/v1'),
  DATABASE_URL: Joi.string()
    .uri({ scheme: ['postgres', 'postgresql'] })
    .optional(),
  CORS_ORIGINS: Joi.string().allow('').default('http://localhost:3000'),
  JWT_ACCESS_SECRET: Joi.string().allow('').optional(),
  JWT_REFRESH_SECRET: Joi.string().allow('').optional(),
  OTP_PEPPER: Joi.string().allow('').optional(),
  AUDIT_CHAIN_SECRET: Joi.string().allow('').optional(),
  OTP_TTL_SECONDS: Joi.number().positive().default(600),
  OTP_MAX_ATTEMPTS: Joi.number().integer().positive().default(5),
  OTP_LOCKOUT_SECONDS: Joi.number().positive().default(900),
  OTP_SEND_LIMIT_PER_PHONE_PER_HOUR: Joi.number().integer().positive().default(3),
  OTP_SEND_LIMIT_PER_IP_PER_HOUR: Joi.number().integer().positive().default(10),
  JWT_ACCESS_TTL_SECONDS: Joi.number().positive().default(900),
  JWT_REFRESH_TTL_SECONDS: Joi.number().positive().default(2592000),
  FOLLOW_UP_SCHEDULER_ENABLED: Joi.boolean().default(true),
  FOLLOW_UP_SCHEDULER_INTERVAL_SECONDS: Joi.number().integer().min(10).max(86400).default(60),
});
