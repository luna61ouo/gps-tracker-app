import '../config.dart';
import 'app_strings.dart';

class AppStringsZh extends AppStrings {
  // ── App ──────────────────────────────────────────────────────────────────
  @override String get appTitle => 'OpenClaw GPS';

  // ── AppBar ───────────────────────────────────────────────────────────────
  @override String get tooltipSettings => '設定';
  @override String get tooltipHelp => '說明';

  // ── Help dialog ──────────────────────────────────────────────────────────
  @override String get helpTitle => '關於 OpenClaw GPS';
  @override String get helpIntro =>
      'OpenClaw GPS 是專為 OpenClaw AI 助理設計的背景定位工具。';
  @override String get helpHowTitle => '運作方式：';
  @override String get helpHow1 => '1. 手機依設定間隔取得 GPS 座標';
  @override String get helpHow2 => '2. 座標經過端對端加密（X25519 + AES-256-GCM）';
  @override String get helpHow3 => '3. 透過中繼伺服器傳送給你的電腦';
  @override String get helpHow4 => '4. OpenClaw 可以詢問你目前的位置與歷史軌跡';
  @override String get helpModeTitle => '提取確認方式：';
  @override String get helpModeAuto => '・自動：持續推送，OpenClaw 可隨時取得位置';
  @override String get helpModeAsk => '・詢問：收到請求時通知你，確認後才回傳';
  @override String get helpModeDeny => '・拒絕：一律不傳送位置';
  @override String get helpHistoryTitle => '歷史追蹤：';
  @override String get helpHistoryDesc =>
      '可設定歷史記錄的時間刻度與保留時間，讓 OpenClaw 查詢過去的移動軌跡，而不需要儲存大量資料。';
  @override String get helpSetupTitle => '設定方式：';
  @override String get helpSetupDesc =>
      '在 OpenClaw 中安裝 gps-bridge，它會提供你 Token 和公鑰，輸入到本 App 的設定中即可完成配對。';
  @override String get helpPrivacy =>
      '資料安全：伺服器只轉送加密資料，無法讀取你的位置。';

  // ── Common buttons ───────────────────────────────────────────────────────
  @override String get btnGotIt => '了解了';
  @override String get btnCancel => '取消';
  @override String get btnAdd => '新增';
  @override String get btnDelete => '刪除';
  @override String get btnGoSettings => '前往設定';

  // ── Status tile ──────────────────────────────────────────────────────────
  @override String get statusTracking => '追蹤中';
  @override String get statusStopped => '已停止';
  @override String get statusNoData => '尚無定位資料';
  @override String get labelGpsError => 'GPS 錯誤';
  @override String get labelLat => '緯度';
  @override String get labelLng => '經度';
  @override String get labelGpsRecord => 'GPS 紀錄';
  @override String get labelSentAt => '傳送時間';
  @override String get labelSendStatus => '傳送狀態';
  @override String get statusNoDataHint => '尚無定位資料，請按下方按鈕開始追蹤';

  // ── Tracking button ──────────────────────────────────────────────────────
  @override String get btnStop => '停止追蹤';
  @override String get btnStart => '開始追蹤';
  @override String get btnSubtitle =>
      '依設定間隔自動更新 GPS\n端對端加密傳送給 OpenClaw';

  // ── Self-check warnings ───────────────────────────────────────────────────
  @override String get warnNoLocationPerm =>
      '尚未允許定位權限';
  @override String get warnLocationWhileInUse =>
      '目前為「使用期間」定位，建議改為「永遠允許」以確保背景追蹤正常';
  @override String get warnNoPubKey => '尚未設定伺服器公鑰';
  @override String get warnNoRelay => '尚未設定 Relay 伺服器';
  @override String get warnNoToken => '尚未設定配對碼（Token）';
  @override String get warnNeedBgPerm =>
      '需要背景定位權限\n請至設定開啟「永遠允許」定位';

  // ── Settings page ─────────────────────────────────────────────────────────
  @override String get settingsTitle => '設定';

  // Relay section
  @override String get sectionRelay => '中繼資料轉送伺服器';
  @override String get relayDropdownHint => '尚未設定，請點 + 新增';
  @override String get relayOfficialLabel => '官方路由';
  @override String get relayAddTitle => '新增 Relay 伺服器';
  @override String get relayAddHint => 'wss://example.com/relay';
  @override String get relayDeleteTitle => '刪除伺服器';
  @override String relayDeleteConfirm(String url) => '確定要刪除？\n$url';
  // Relay info dialog
  @override String get relayInfoTitle => '中繼資料轉送伺服器';
  @override String get relayInfoWhatTitle => '什麼是中繼伺服器？';
  @override String get relayInfoWhatBody =>
      '大多數電腦沒有公開 IP，無法直接從外部接收連線。'
      '中繼伺服器架設在網際網路上，負責在手機與 OpenClaw 之間轉送加密資料。';
  @override String get relayInfoSecurityTitle => '資料安全';
  @override String get relayInfoSecurityBody =>
      '中繼伺服器只負責轉送，不會解密或儲存任何位置資料。'
      '所有資料在傳輸前已由手機端以 X25519 + AES-256-GCM 加密，只有你的 OpenClaw 才能解密。';
  @override String get relayInfoSelfHostTitle => '自架中繼伺服器';
  @override String get relayInfoSelfHostBody =>
      '若你有公開 IP 或自己的伺服器，可以自行部署 gps-relay 作為私人中繼節點，完全掌控資料流向。\n\n'
      '原始碼與教學請參考：\n$kGithubRelayDisplay';

  // Confirm mode section
  @override String get sectionConfirmMode => '提取確認方式';
  @override String get confirmModeAuto => '自動（持續推送）';
  @override String get confirmModeAsk => '詢問（OpenClaw 請求時通知）';
  @override String get confirmModeDeny => '拒絕（不傳送位置）';
  @override String get confirmHintAuto => 'OpenClaw 可隨時取得最新位置';
  @override String get confirmHintAsk => '收到請求時顯示通知，確認後才回傳位置';
  @override String get confirmHintDeny => 'OpenClaw 的請求一律被拒絕';

  // Update interval section
  @override String get sectionInterval => '更新間隔';
  @override String get intervalFgNote => '開啟 App 時固定每 5 秒更新';
  @override String intervalSec(int n) => '$n 秒';
  @override String intervalMin(int n) => '$n 分鐘';
  @override String intervalHour(int n) => '$n 小時';
  @override String withDefault(String base) => '$base（預設）';

  // History section
  @override String get sectionHistory => '歷史追蹤';
  @override String get historyNote =>
      '以下設定控制 OpenClaw Bridge（電腦端）資料庫的歷史紀錄行為，手機僅負責依設定標記每筆資料是否儲存。';
  @override String get historyGranularityLabel => '歷史記錄時間刻度';
  @override String get historyGranularityHint =>
      'Bridge 每隔多久在資料庫存入一筆歷史座標';
  @override String get historyRetentionLabel => '歷史資料保留時間';
  @override String get historyRetentionHint =>
      'Bridge 資料庫自動刪除超過此時間的歷史記錄';
  @override String get historyNoSave => '不儲存歷史';
  @override String retentionHour(int n) => '$n 小時';
  @override String retentionDay(int n) => '$n 天';
  @override String retentionWeek(int n) => '$n 週';
  @override String retentionMonth(int n) => '$n 個月';
  @override String get retentionUnlimited => '無上限';

  // Pairing section
  @override String get sectionPairing => '配對設定';
  @override String get pairingHelpTitle => '如何取得配對資訊？';
  @override String get pairingHelpBody =>
      '配對碼和公鑰由 OpenClaw 的 gps-bridge 產生。\n\n'
      '請在 OpenClaw 中說：\n\n'
      '「我想設定 GPS 追蹤，幫我產生配對碼」\n\n'
      'OpenClaw 會自動：\n'
      '1. 產生 Bridge 公鑰\n'
      '2. 產生配對碼（Token）\n'
      '3. 啟動接收器等待連線\n\n'
      '把 OpenClaw 提供的公鑰和配對碼貼到下方欄位即可。';
  @override String get labelToken => 'Token（配對碼）';
  @override String get labelTokenHint => '由 OpenClaw 提供';
  @override String get labelPubKey => 'Bridge 公鑰';
  @override String get labelPubKeyHint => '由 OpenClaw 提供（Base64）';

  // Advanced section
  @override String get sectionAdvanced => '進階設定';
  @override String get batteryModeTitle => '定位加強模式';
  @override String get batteryModeOnDesc => '已停用電池優化，背景追蹤更穩定';
  @override String get batteryModeOffDesc =>
      '停用系統電池優化，適合部分 Android 裝置（如 Xiaomi）避免背景服務被終止。Pixel 等原廠裝置通常不需要。';
  // Timezone section
  @override String get sectionTimezone => '顯示時區';
  @override String get timezoneAuto => '自動（系統）';

  // Guide / links section
  @override String get sectionGuide => '說明與教學';
  @override String get guideTutorialTitle => '安裝與設定教學';
  @override String get guideTutorialSubtitle => '如何搭配 OpenClaw 使用';
  @override String get guideBridgeTitle => 'gps-bridge 原始碼';
  @override String get guideBridgeSubtitle => kGithubBridgeDisplay;
  @override String get guideRelayTitle => 'gps-relay 原始碼';
  @override String get guideRelaySubtitle => kGithubRelayDisplay;

  // Language section
  @override String get sectionLanguage => '語言';
  @override String get langAuto => '自動';
  @override String get langZh => '中文';
  @override String get langEn => 'English';
}
