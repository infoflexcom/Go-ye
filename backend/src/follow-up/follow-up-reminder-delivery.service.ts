import { Injectable, Logger, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomUUID } from 'node:crypto';
import { FcmPushError, FcmPushGatewayService } from './fcm-push-gateway.service.js';
import { FollowUpReminderQueueService } from './follow-up-reminder-queue.service.js';
import { FollowUpTasksService } from './follow-up-tasks.service.js';

@Injectable()
export class FollowUpReminderDeliveryService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(FollowUpReminderDeliveryService.name);
  private interval?: NodeJS.Timeout;
  private deliveryInProgress = false;

  constructor(
    private readonly reminderQueue: FollowUpReminderQueueService,
    private readonly tasks: FollowUpTasksService,
    private readonly fcm: FcmPushGatewayService,
    private readonly config: ConfigService,
  ) {}

  async onModuleInit(): Promise<void> {
    if (!this.fcm.isConfigured()) {
      return;
    }
    await this.deliverSafely();
    this.interval = setInterval(() => {
      void this.deliverSafely();
    }, this.intervalMilliseconds());
    this.interval.unref();
  }

  onModuleDestroy(): void {
    if (this.interval) {
      clearInterval(this.interval);
    }
  }

  async deliverOnce(now: Date = new Date()): Promise<number> {
    if (!this.fcm.isConfigured()) {
      return 0;
    }
    const workerId = randomUUID();
    const jobs = await this.reminderQueue.claim(workerId, 25, now);
    let handled = 0;
    for (const job of jobs) {
      const recipients = await this.tasks.eligiblePushRecipients(job.followUpTaskId);
      if (!recipients.taskIsActive) {
        await this.reminderQueue.markDelivered(job.id, workerId, now);
        handled += 1;
        continue;
      }
      if (recipients.tokens.length === 0) {
        await this.reminderQueue.retry(
          job.id,
          workerId,
          'NO_ELIGIBLE_DEVICE',
          this.retryAt(now, job.attempts),
          now,
        );
        continue;
      }

      let retryableFailure = false;
      let deliveredToAtLeastOneDevice = false;
      for (const recipient of recipients.tokens) {
        try {
          await this.fcm.sendDueReminder({
            token: recipient.token,
            reminderJobId: job.id,
            followUpTaskId: job.followUpTaskId,
            idempotencyKey: job.idempotencyKey,
          });
          deliveredToAtLeastOneDevice = true;
        } catch (error) {
          if (error instanceof FcmPushError && error.code === 'FCM_TOKEN_INVALID') {
            await this.tasks.clearPushToken(recipient.deviceId);
          } else {
            retryableFailure = true;
          }
        }
      }

      if (retryableFailure || !deliveredToAtLeastOneDevice) {
        await this.reminderQueue.retry(
          job.id,
          workerId,
          retryableFailure ? 'FCM_TRANSIENT_FAILURE' : 'NO_ELIGIBLE_DEVICE',
          this.retryAt(now, job.attempts),
          now,
        );
      } else {
        await this.reminderQueue.markDelivered(job.id, workerId, now);
        handled += 1;
      }
    }
    return handled;
  }

  private async deliverSafely(): Promise<void> {
    if (this.deliveryInProgress) {
      return;
    }
    this.deliveryInProgress = true;
    try {
      const delivered = await this.deliverOnce();
      if (delivered > 0) {
        this.logger.log(`Delivered ${delivered} follow-up reminder job(s) through FCM.`);
      }
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown FCM delivery failure';
      this.logger.error(`Follow-up FCM delivery run failed: ${message}`);
    } finally {
      this.deliveryInProgress = false;
    }
  }

  private retryAt(now: Date, attempts: number): Date {
    const delayMinutes = Math.min(60, 2 ** Math.max(0, attempts - 1));
    return new Date(now.getTime() + delayMinutes * 60_000);
  }

  private intervalMilliseconds(): number {
    return this.config.get<number>('FCM_DELIVERY_INTERVAL_SECONDS', 30) * 1000;
  }
}
