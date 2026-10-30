import { Counter, Trend } from "k6/metrics"

export const wsConnectOk = new Counter("tradetraxs_ws_connect_ok")
export const wsConnectFail = new Counter("tradetraxs_ws_connect_fail")
export const wsSubscribeOk = new Counter("tradetraxs_ws_subscribe_ok")
export const wsSubscribeFail = new Counter("tradetraxs_ws_subscribe_fail")

export const dmSendOk = new Counter("tradetraxs_dm_send_ok")
export const dmSendFail = new Counter("tradetraxs_dm_send_fail")
export const roomSendOk = new Counter("tradetraxs_room_send_ok")
export const roomSendFail = new Counter("tradetraxs_room_send_fail")

/** Latency for correlated postgres_changes (insert → event), successful deliveries only. */
export const realtimeDeliveryMs = new Trend("tradetraxs_realtime_delivery_ms", true)
/** @deprecated use deliverySuccess / deliveryTimeout / deliverySubscribeFail */
export const realtimeDeliveryMiss = new Counter("tradetraxs_realtime_delivery_miss")

export const realtimeDeliverySuccess = new Counter("tradetraxs_realtime_delivery_success")
export const realtimeDeliveryTimeout = new Counter("tradetraxs_realtime_delivery_timeout")
export const realtimeDeliverySubscribeFail = new Counter("tradetraxs_realtime_delivery_subscribe_fail")

export const dmSendAttempt = new Counter("tradetraxs_dm_send_attempt")
export const roomSendAttempt = new Counter("tradetraxs_room_send_attempt")

export const messagingBootstrapMs = new Trend("tradetraxs_messaging_bootstrap_ms", true)
export const dmThreadBootstrapMs = new Trend("tradetraxs_dm_thread_bootstrap_ms", true)
