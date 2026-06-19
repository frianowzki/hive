import { BigInt } from "@graphprotocol/graph-ts";
import {
  NotificationSent,
  PriceAlertSet,
  PriceAlertTriggered
} from "../generated/HiveNotification/HiveNotification";
import {
  Notification,
  PriceAlert
} from "../generated/schema";

export function handleNotificationSent(event: NotificationSent): void {
  let notificationId = event.params.user.toHex() + "-" + event.block.timestamp.toString();
  let notification = new Notification(notificationId);
  notification.user = event.params.user;
  notification.title = event.params.title;
  notification.message = event.params.message;
  notification.timestamp = event.block.timestamp;
  notification.read = false;

  // Map event type
  let eventType = event.params.eventType;
  if (eventType == 0) {
    notification.eventType = "SALE_START";
  } else if (eventType == 1) {
    notification.eventType = "SALE_END";
  } else if (eventType == 2) {
    notification.eventType = "PRICE_ALERT";
  } else if (eventType == 3) {
    notification.eventType = "STRATEGY_EXEC";
  } else if (eventType == 4) {
    notification.eventType = "GOVERNANCE_VOTE";
  } else if (eventType == 5) {
    notification.eventType = "REPUTATION_CHANGE";
  } else if (eventType == 6) {
    notification.eventType = "STAKE_CHANGE";
  } else if (eventType == 7) {
    notification.eventType = "REFERRAL_BONUS";
  } else if (eventType == 8) {
    notification.eventType = "TREASURY_DIST";
  } else {
    notification.eventType = "BRAIN_ACTION";
  }

  notification.save();
}

export function handlePriceAlertSet(event: PriceAlertSet): void {
  let alertId = event.params.user.toHex() + "-" + event.params.alertId.toString();
  let alert = new PriceAlert(alertId);
  alert.user = event.params.user;
  alert.alertId = event.params.alertId;
  alert.token = event.params.token;
  alert.threshold = event.params.threshold;
  alert.above = event.params.above;
  alert.active = true;
  alert.createdAt = event.block.timestamp;
  alert.save();
}

export function handlePriceAlertTriggered(event: PriceAlertTriggered): void {
  let alertId = event.params.user.toHex() + "-" + event.params.alertId.toString();
  let alert = PriceAlert.load(alertId);
  if (alert) {
    alert.active = false;
    alert.save();
  }
}
