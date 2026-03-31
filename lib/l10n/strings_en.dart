import '../config.dart';
import 'app_strings.dart';

class AppStringsEn extends AppStrings {
  // ── App ──────────────────────────────────────────────────────────────────
  @override String get appTitle => 'OpenClaw GPS';

  // ── AppBar ───────────────────────────────────────────────────────────────
  @override String get tooltipSettings => 'Settings';
  @override String get tooltipHelp => 'Help';

  // ── Help dialog ──────────────────────────────────────────────────────────
  @override String get helpTitle => 'About OpenClaw GPS';
  @override String get helpIntro =>
      'OpenClaw GPS is a background location tracking tool designed for the OpenClaw AI assistant.';
  @override String get helpHowTitle => 'How it works:';
  @override String get helpHow1 => '1. The phone acquires GPS coordinates at the configured interval';
  @override String get helpHow2 => '2. Coordinates are end-to-end encrypted (X25519 + AES-256-GCM)';
  @override String get helpHow3 => '3. Sent to your computer via a relay server';
  @override String get helpHow4 => '4. OpenClaw can query your current location and movement history';
  @override String get helpModeTitle => 'Sharing mode:';
  @override String get helpModeAuto => '· Auto: continuous push — OpenClaw can get your location anytime';
  @override String get helpModeAsk => '· Ask: notifies you when a request arrives, location sent after confirmation';
  @override String get helpModeDeny => '· Deny: never sends location';
  @override String get helpHistoryTitle => 'History tracking:';
  @override String get helpHistoryDesc =>
      'Configure the history granularity and retention period so OpenClaw can query your past movement trail without storing large amounts of data.';
  @override String get helpSetupTitle => 'Setup:';
  @override String get helpSetupDesc =>
      'Install gps-bridge in OpenClaw — it will provide you with a Token and public key. Enter these in the app settings to complete pairing.';
  @override String get helpPrivacy =>
      'Security: the relay server only forwards encrypted data and cannot read your location.';

  // ── Onboarding ──────────────────────────────────────────────────────────
  @override String get onboardingPage1Title => 'Privacy-first GPS Tracking';
  @override String get onboardingPage1Body =>
      'End-to-end encrypted — only your own computer can decrypt your location.\nThe relay server only forwards ciphertext.';
  @override String get onboardingPage2Title => 'How it works';
  @override String get onboardingPage2Body =>
      'Phone encrypts GPS → forwarded through relay → your computer decrypts and stores.\nOpenClaw queries your location locally.';
  @override String get onboardingPage3Title => 'Quick Setup';
  @override String get onboardingPage3Body =>
      'Go to Settings → tap "Install Bridge"\n→ Copy the instructions to OpenClaw\n→ OpenClaw provides a pairing token and public key\n→ Enter them and start tracking';
  @override String get onboardingNext => 'Next';
  @override String get onboardingStart => 'Get Started';

  // ── Common buttons ───────────────────────────────────────────────────────
  @override String get btnGotIt => 'Got it';
  @override String get btnCancel => 'Cancel';
  @override String get btnAdd => 'Add';
  @override String get btnDelete => 'Delete';
  @override String get btnCopy => 'Copy';
  @override String get btnGoSettings => 'Go to Settings';

  // ── Status tile ──────────────────────────────────────────────────────────
  @override String get statusTracking => 'Tracking';
  @override String get statusStopped => 'Stopped';
  @override String get statusNoData => 'No location data';
  @override String get labelGpsError => 'GPS Error';
  @override String get labelLat => 'Latitude';
  @override String get labelLng => 'Longitude';
  @override String get labelGpsRecord => 'GPS Record';
  @override String get labelSentAt => 'Sent At';
  @override String get labelSendStatus => 'Send Status';
  @override String get statusNoDataHint =>
      'No location data — tap the button below to start tracking';
  @override String get labelConfirmedAt => 'Delivery confirmed';
  @override String get labelUnconfirmed => 'Bridge has not confirmed receipt — check that gps-bridge connect is running';

  // ── Tracking button ──────────────────────────────────────────────────────
  @override String get btnStop => 'Stop Tracking';
  @override String get btnStart => 'Start Tracking';
  @override String get btnSubtitle =>
      'GPS updates automatically at the configured interval\nEnd-to-end encrypted and sent to OpenClaw';

  // ── Self-check warnings ───────────────────────────────────────────────────
  @override String get warnNoLocationPerm =>
      'Location permission not granted';
  @override String get warnLocationWhileInUse =>
      'Currently set to "While In Use" — change to "Always Allow" for reliable background tracking';
  @override String get warnNoPubKey => 'Server public key not configured';
  @override String get warnNoRelay => 'Relay server not configured';
  @override String get warnNoToken => 'Pairing token not configured';
  @override String get warnMissingPairing => 'Please complete pairing setup: ';
  @override String get warnNeedBgPerm =>
      'Background location permission required\nGo to Settings and enable "Always Allow" location';
  @override String get warnConnectionChanged =>
      'Connection settings changed. Tracking stopped. Please go back and restart tracking.';

  // ── Settings page ─────────────────────────────────────────────────────────
  @override String get settingsTitle => 'Settings';

  // Relay section
  @override String get sectionRelay => 'Relay Server';
  @override String get relayDropdownHint => 'Not configured — tap + to add';
  @override String get relayOfficialLabel => 'Default Relay';
  @override String get relayAddTitle => 'Add Relay Server';
  @override String get relayAddHint => 'wss://example.com/relay';
  @override String get relayDeleteTitle => 'Delete Server';
  @override String relayDeleteConfirm(String url) => 'Delete this server?\n$url';
  // Relay info dialog
  @override String get relayInfoTitle => 'Relay Server';
  @override String get relayInfoWhatTitle => 'What is a relay server?';
  @override String get relayInfoWhatBody =>
      'Most computers don\'t have a public IP and cannot receive connections from the internet. '
      'The relay server sits on the internet and forwards encrypted data between your phone and OpenClaw.';
  @override String get relayInfoSecurityTitle => 'Data security';
  @override String get relayInfoSecurityBody =>
      'The relay only forwards data — it never decrypts or stores any location data. '
      'All data is encrypted on the phone using X25519 + AES-256-GCM before transmission, and only your OpenClaw can decrypt it.';
  @override String get relayInfoSelfHostTitle => 'Self-hosting';
  @override String get relayInfoSelfHostBody =>
      'If you have a public IP or your own server, you can deploy gps-relay as a private relay node and have full control over the data flow.\n\n'
      'Source code and setup guide:\n$kGithubRelayDisplay';

  // Confirm mode section
  @override String get sectionConfirmMode => 'Sharing Mode';
  @override String get confirmModeAuto => 'Auto (continuous push)';
  @override String get confirmModeAsk => 'Ask (notify when OpenClaw requests)';
  @override String get confirmModeDeny => 'Deny (never send location)';
  @override String get confirmHintAuto => 'OpenClaw can get your latest location at any time';
  @override String get confirmHintAsk =>
      'Sends a notification on request; location is sent after confirmation';
  @override String get confirmHintDeny => 'All requests from OpenClaw are rejected';

  // Update interval section
  @override String get sectionInterval => 'Update Interval';
  @override String get intervalFgNote => 'Updates every 5 seconds when the app is open';
  @override String intervalSec(int n) => '$n sec';
  @override String intervalMin(int n) => '${n ~/ 1} min';
  @override String intervalHour(int n) => '$n hr';
  @override String withDefault(String base) => '$base (default)';

  // History section
  @override String get sectionHistory => 'History Tracking';
  @override String get historyNote =>
      'The settings below control history recording in the OpenClaw Bridge (PC-side) database. '
      'The phone only marks each data point according to the configured interval.';
  @override String get historyGranularityLabel => 'History granularity';
  @override String get historyGranularityHint =>
      'How often Bridge saves a history waypoint to the database';
  @override String get historyRetentionLabel => 'History retention';
  @override String get historyRetentionHint =>
      'Bridge automatically deletes history records older than this';
  @override String get historyNoSave => 'Do not save history';
  @override String retentionHour(int n) => '$n hr';
  @override String retentionDay(int n) => n == 1 ? '1 day' : '$n days';
  @override String retentionWeek(int n) => n == 1 ? '1 week' : '$n weeks';
  @override String retentionMonth(int n) => n == 1 ? '1 month' : '$n months';
  @override String get retentionUnlimited => 'Unlimited';

  // Install Bridge section
  @override String get sectionInstallBridge => 'Install Bridge';
  @override String get installBridgeTitle => 'Copy instructions for OpenClaw';
  @override String get installBridgeSubtitle => 'Let OpenClaw install GPS Bridge automatically';
  @override String get installBridgeDialogTitle => 'Install GPS Bridge';
  @override String get installBridgeDialogBody =>
      'Copy the text below and paste it to OpenClaw:\n\n'
      '---\n'
      'Please install GPS Bridge to receive encrypted GPS coordinates from my phone.\n\n'
      'pip install gps-bridge\n\n'
      'After installation, help me set up GPS tracking (generate keypair and pairing token).\n\n'
      'Project info: https://github.com/luna61ouo/gps-bridge\n'
      '---';
  @override String get installBridgeCopied => 'Copied! Paste it to OpenClaw.';

  // Pairing section
  @override String get sectionPairing => 'Pairing';
  @override String get pairingHelpTitle => 'How to get pairing info?';
  @override String get pairingHelpBody =>
      'The pairing code and public key are generated by gps-bridge in OpenClaw.\n\n'
      'Tell OpenClaw:\n\n'
      '"I want to set up GPS tracking, generate a pairing code"\n\n'
      'OpenClaw will automatically:\n'
      '1. Generate the Bridge public key\n'
      '2. Generate a pairing token\n'
      '3. Start the receiver and wait for connection\n\n'
      'Paste the public key and token provided by OpenClaw into the fields below.';
  @override String get labelToken => 'Token (Pairing Code)';
  @override String get labelTokenHint => 'Provided by OpenClaw';
  @override String get labelPubKey => 'Bridge Public Key';
  @override String get labelPubKeyHint => 'Provided by OpenClaw (Base64)';

  // Advanced section
  @override String get sectionAdvanced => 'Advanced';
  @override String get batteryModeTitle => 'Enhanced Location Mode';
  @override String get batteryModeOnDesc =>
      'Battery optimization disabled — background tracking is more stable';
  @override String get batteryModeOffDesc =>
      'Disable system battery optimization. Recommended for some Android devices (e.g. Xiaomi) '
      'that aggressively kill background services. Usually not needed on Pixel devices.';
  // Timezone section
  @override String get sectionTimezone => 'Display Timezone';
  @override String get timezoneAuto => 'Auto (system)';

  // Guide / links section
  @override String get sectionGuide => 'Documentation';
  @override String get guideTutorialTitle => 'Installation & Setup Guide';
  @override String get guideTutorialSubtitle => 'How to use with OpenClaw';
  @override String get guideTutorialBody =>
      '【Step 1】Install Bridge\n'
      'Tap "Install Bridge" at the top of Settings, copy the command and paste it to OpenClaw.\n'
      'OpenClaw will automatically install gps-bridge.\n\n'
      '【Step 2】Get pairing token and public key\n'
      'After installation, tell OpenClaw: "Help me set up GPS tracking."\n'
      'OpenClaw will generate:\n'
      '  - Pairing token\n'
      '  - Bridge public key\n\n'
      '【Step 3】Enter pairing info\n'
      'In the "Pairing" section below,\n'
      'enter the Token and Bridge public key.\n\n'
      '【Step 4】Start tracking\n'
      'Go back to the main page and tap "Start Tracking".\n'
      'Your phone will automatically encrypt and send GPS to your computer.\n\n'
      '【Verify】\n'
      'Tell OpenClaw: "Where am I?"\n'
      'If it can answer your location, pairing is successful!\n\n'
      'Note: The phone showing "sending" does NOT confirm correct pairing.\n'
      'The only way to verify is that OpenClaw can read your location.';
  @override String get guideBridgeTitle => 'gps-bridge Source Code';
  @override String get guideBridgeSubtitle => kGithubBridgeDisplay;
  @override String get guideRelayTitle => 'gps-relay Source Code';
  @override String get guideRelaySubtitle => kGithubRelayDisplay;
  @override String get guideReplayTitle => 'Replay Setup Guide';
  @override String get guideReplaySubtitle => 'Show the first-launch setup guide again';

  // Send log section
  @override String get sendLogTitle => 'Send Log';
  @override String get sendLogEmpty => 'No send records yet';
  @override String get sendLogStatusSent => 'Sent';
  @override String get sendLogStatusConfirmed => 'Confirmed';
  @override String get sendLogStatusFailed => 'Failed';
  @override String get sendLogStatusQueued => 'Queued';
  @override String get sendLogClear => 'Clear Log';
  @override String get sendLogClearConfirm => 'Clear all send records?';

  // Language section
  @override String get sectionLanguage => 'Language';
  @override String get langAuto => 'Auto';
  @override String get langZh => '中文';
  @override String get langEn => 'English';
}
