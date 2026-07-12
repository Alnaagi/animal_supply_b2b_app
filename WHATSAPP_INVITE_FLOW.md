# WhatsApp Invite Flow

## Flow

1. Admin creates business customer.
2. Edge Function creates Auth user.
3. Edge Function generates temporary password.
4. Edge Function generates one-time invite token.
5. Admin copies or sends WhatsApp message.
6. Customer downloads app.
7. Invite link opens app and pre-fills token/client code.
8. Customer enters temporary password manually.
9. App requires password change on first login in production.

## Arabic Template

```text
مرحباً {business_name} 👋
تم إنشاء حسابكم في تطبيق {shop_name} لطلب أعلاف ومستلزمات الحيوانات بالجملة.

بيانات الدخول:
اسم المستخدم: {username}
كلمة المرور المؤقتة: {temporary_password}

رابط تحميل التطبيق:
{download_link}

رابط تفعيل الحساب:
{invite_link}

ملاحظة: حفاظاً على أمان حسابكم، يرجى تغيير كلمة المرور بعد أول تسجيل دخول.
```

## Security Rule

`{invite_link}` must not include `{temporary_password}`. It may include only a token and optional client code.
