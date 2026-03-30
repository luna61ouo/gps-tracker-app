/// Abstract base class for all app UI strings.
///
/// To add a new language:
/// 1. Create a new file, e.g. strings_ja.dart
/// 2. Extend this class and implement every getter/method
/// 3. Register it in resolveStrings() inside localizations.dart
abstract class AppStrings {
  // ── App ──────────────────────────────────────────────────────────────────
  String get appTitle;

  // ── AppBar ───────────────────────────────────────────────────────────────
  String get tooltipSettings;
  String get tooltipHelp;

  // ── Help dialog ──────────────────────────────────────────────────────────
  String get helpTitle;
  String get helpIntro;
  String get helpHowTitle;
  String get helpHow1;
  String get helpHow2;
  String get helpHow3;
  String get helpHow4;
  String get helpModeTitle;
  String get helpModeAuto;
  String get helpModeAsk;
  String get helpModeDeny;
  String get helpHistoryTitle;
  String get helpHistoryDesc;
  String get helpSetupTitle;
  String get helpSetupDesc;
  String get helpPrivacy;

  // ── Common buttons ───────────────────────────────────────────────────────
  String get btnGotIt;
  String get btnCancel;
  String get btnAdd;
  String get btnDelete;
  String get btnGoSettings;

  // ── Status tile ──────────────────────────────────────────────────────────
  String get statusTracking;
  String get statusStopped;
  String get statusNoData;
  String get labelGpsError;
  String get labelLat;
  String get labelLng;
  String get labelGpsRecord;
  String get labelSentAt;
  String get labelSendStatus;
  String get statusNoDataHint;

  // ── Tracking button ──────────────────────────────────────────────────────
  String get btnStop;
  String get btnStart;
  String get btnSubtitle;

  // ── Self-check warnings ───────────────────────────────────────────────────
  String get warnNoLocationPerm;
  String get warnNoPubKey;
  String get warnNoRelay;
  String get warnNoToken;
  String get warnNeedBgPerm;

  // ── Settings page ─────────────────────────────────────────────────────────
  String get settingsTitle;

  // Relay section
  String get sectionRelay;
  String get relayDropdownHint;
  String get relayOfficialLabel;
  String get relayAddTitle;
  String get relayAddHint;
  String get relayDeleteTitle;
  String relayDeleteConfirm(String url);
  // Relay info dialog
  String get relayInfoTitle;
  String get relayInfoWhatTitle;
  String get relayInfoWhatBody;
  String get relayInfoSecurityTitle;
  String get relayInfoSecurityBody;
  String get relayInfoSelfHostTitle;
  String get relayInfoSelfHostBody;

  // Confirm mode section
  String get sectionConfirmMode;
  String get confirmModeAuto;
  String get confirmModeAsk;
  String get confirmModeDeny;
  String get confirmHintAuto;
  String get confirmHintAsk;
  String get confirmHintDeny;

  // Update interval section
  String get sectionInterval;
  String get intervalFgNote;
  String intervalSec(int n);
  String intervalMin(int n);
  String intervalHour(int n);
  String withDefault(String base);

  // History section
  String get sectionHistory;
  String get historyNote;
  String get historyGranularityLabel;
  String get historyGranularityHint;
  String get historyRetentionLabel;
  String get historyRetentionHint;
  String get historyNoSave;
  String retentionHour(int n);
  String retentionDay(int n);
  String retentionWeek(int n);
  String retentionMonth(int n);
  String get retentionUnlimited;

  // Pairing section
  String get sectionPairing;
  String get labelToken;
  String get labelTokenHint;
  String get labelPubKey;
  String get labelPubKeyHint;

  // Advanced section (Android only)
  String get sectionAdvanced;
  String get batteryModeTitle;
  String get batteryModeOnDesc;
  String get batteryModeOffDesc;
  // Timezone section
  String get sectionTimezone;
  String get timezoneAuto;

  // Guide / links section
  String get sectionGuide;
  String get guideTutorialTitle;
  String get guideTutorialSubtitle;
  String get guideBridgeTitle;
  String get guideBridgeSubtitle;
  String get guideRelayTitle;
  String get guideRelaySubtitle;

  // Language section
  String get sectionLanguage;
  String get langAuto;
  String get langZh;
  String get langEn;
}
