/** R|Protocol template IDs from official package 0.89.0.0 (see samples/samples.py/SampleOrder.py). */

export const RITHMIC_TEMPLATE_VERSION = "3.9"

export const RithmicTemplateId = {
  RequestRithmicSystemInfo: 16,
  RequestLogin: 10,
  ResponseLogin: 11,
  RequestLogout: 12,
  ResponseLogout: 13,
  RequestHeartbeat: 18,
  ResponseHeartbeat: 19,
  RequestLoginInfo: 300,
  ResponseLoginInfo: 301,
  RequestAccountList: 302,
  ResponseAccountList: 303,
  RequestShowFillHistory: 3512,
  ResponseShowFillHistory: 3513,
} as const

export const RITHMIC_FILL_HISTORY_MAX_RECORD_COUNT = 10_000

/** request_login.proto SysInfraType */
export const RithmicInfraType = {
  TICKER_PLANT: 1,
  ORDER_PLANT: 2,
  HISTORY_PLANT: 3,
  PNL_PLANT: 4,
  REPOSITORY_PLANT: 5,
} as const
