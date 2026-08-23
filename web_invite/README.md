# Invite links — the web half

Two files, for the day you own a domain. Nothing here runs today, and nothing
here needs to change when the app changes.

## What these are

| File | Job |
|---|---|
| `.well-known/assetlinks.json` | Tells Android "this app may handle my links". |
| `join.html` | What someone **without** the app sees. Shows the code and offers to open the app. |

If Jirends is installed and App Links are verified, Android intercepts the URL
before a browser is ever involved and `join.html` is never fetched. It only
exists for people who don't have the app.

## Deploying

1. Register a domain (~€10/yr). The app currently builds links against
   `jirends.app`; if you pick something else, change `inviteLink()` in
   `lib/features/events/presentation/event_detail_screen.dart` and the
   `android:host` in `AndroidManifest.xml` to match.

2. Host this directory on any static host with HTTPS — Netlify, Vercel,
   Cloudflare Pages and GitHub Pages are all free and all fine. HTTPS is not
   optional: App Links will not verify over plain HTTP.

3. Add a rewrite so `/join/<anything>` serves `join.html`. On Netlify that is a
   `_redirects` file containing:

   ```
   /join/*  /join.html  200
   ```

4. Confirm `https://<domain>/.well-known/assetlinks.json` returns the JSON with
   `Content-Type: application/json` and **no redirect**. Android will not follow
   one.

5. Add the https intent-filter to `AndroidManifest.xml`, beside the existing
   `jirends://` one:

   ```xml
   <intent-filter android:autoVerify="true">
       <action android:name="android.intent.action.VIEW"/>
       <category android:name="android.intent.category.DEFAULT"/>
       <category android:name="android.intent.category.BROWSABLE"/>
       <data android:scheme="https" android:host="jirends.app" android:pathPrefix="/join"/>
   </intent-filter>
   ```

6. Point `inviteLink()` at `https://` instead of `jirends://`. That single word
   is the whole app-side change — the path `/join/<token>` is already identical
   in both, which is why the host was set to `jirends.app` from the start.

## The fingerprint — read this before it bites you

`assetlinks.json` currently carries the **debug** signing fingerprint, because
that is what signs the app today:

```
B6:7E:59:47:1F:A1:1A:50:2F:69:CE:E6:5A:87:29:3D:54:0F:C1:B4:18:37:99:D4:EA:4D:64:97:56:F7:BA:FB
```

That fingerprint belongs to a keystore generated on one machine and backed up
nowhere. **Create a real release keystore before publishing this file**, and put
that fingerprint here instead — otherwise you will publish a verification for a
key you cannot reproduce.

Get a keystore's fingerprint with:

```
keytool -list -v -keystore <your.jks> -alias <alias>
```

`sha256_cert_fingerprints` is an array, so when you later move to Play App
Signing you add Google's fingerprint alongside yours and links keep working
from both sources.

## Verifying it worked

```
adb shell pm verify-app-links --re-verify com.jirends.jirends
adb shell pm get-app-links com.jirends.jirends
```

The second should report `verified` for your domain. Google also hosts a
checker at <https://developers.google.com/digital-asset-links/tools/generator>.
