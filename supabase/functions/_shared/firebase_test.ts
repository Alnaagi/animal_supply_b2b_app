import {
  assertEquals,
  assertObjectMatch,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  androidNotificationChannelId,
  firebaseMessagePayload,
} from "./firebase.ts";

Deno.test("Firebase payload uses the Android channel created by Flutter", () => {
  const payload = firebaseMessagePayload({
    token: "device-token",
    title: "تحديث الطلب",
    body: "تم تجهيز طلبك",
    data: {
      order_id: "11111111-1111-4111-8111-111111111111",
      attempt: 2,
    },
  }) as {
    message: {
      data: Record<string, string>;
      android: { notification: { channel_id: string } };
      webpush: { notification: Record<string, unknown> };
    };
  };

  assertEquals(
    payload.message.android.notification.channel_id,
    androidNotificationChannelId,
  );
  assertEquals(payload.message.data.attempt, "2");
  assertObjectMatch(payload.message.webpush.notification, {
    dir: "rtl",
    lang: "ar",
  });
});
