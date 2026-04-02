## 目标与范围

* 在“个人信息”Tab 内新增“体重/体脂秤同步”功能：通过蓝牙连接米家体脂秤 S400，读取测量数据并写入 App。

* 数据落地到 Core Data，并通过现有的 `NSPersistentCloudKitContainer` 自动同步到 iCloud/CloudKit。

* 保留现有“手动同步 iCloud 数据”按钮逻辑（并让新数据也被去重/合并流程覆盖）。

## 现状评估（已确认）

* “个人信息”页面入口与保存逻辑在 [PersonalInfoView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/PersonalInfo/PersonalInfoView.swift)，目前只保存 `UserProfile.weight` 等字段。

* 持久化与 CloudKit 同步在 [Persistence.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Persistence.swift) 使用 `NSPersistentCloudKitContainer`；手动同步会跑 `CoreDataDeduplicator.reconcileAll`。

* 项目目前没有任何 CoreBluetooth/BLE 代码，也没有蓝牙权限描述（[Info.plist](file:///Users/imac/Documents/Projects/MuscleMetric/Config/Info.plist)）。

* Core Data 模型当前没有“体脂/体重历史”实体（[contents](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/MuscleMetric.xcdatamodeld/MuscleMetric.xcdatamodel/contents)）。

## 技术路线（蓝牙侧）

* **优先走标准 GATT 服务**：

  * 扫描并连接包含 Weight Scale(0x181D)/Body Composition(0x181B) 的设备；订阅相应 Measurement characteristic（常见为 0x2A9D/0x2A9C）。

  * 解析 flags 判断“稳定/最终”读数后入库。

* **兼容小米系广播数据的兜底路径**：

  * 一些小米体脂秤会在 BLE 广播的 service data 中直接携带稳定体重与阻抗信息（公开的逆向资料显示其 payload 含 weight/impedance/time/稳定标记）。

  * iOS 扫描时可以从 advertisement 的 service data 直接解析；该模式不一定需要建立连接。

* **体脂获取策略**：

  * 若设备直接上报体脂率/体成分（Body Composition Measurement），则以设备上报为准。

  * 若仅能拿到体重+阻抗：先实现“体脂率估算”作为备用（用阻抗+BIA公式+用户档案 age/height/sex），并在 UI 上明确标注“估算值/设备值”。

## 数据模型与 iCloud 同步（Core Data/CloudKit）

* 新增实体（示例命名）`BodyMeasurement`，并设置 `syncable=YES`，用于保存每次测量记录（历史）：

  * `id: UUID`（必填，用于跨端一致性/去重）

  * `timestamp: Date`（测量时间）

  * `weightKg: Double`（体重）

  * `bodyFatPercent: Double?`（体脂率，可空）

  * `impedance: Int32?`（阻抗，可空）

  * `heartRate: Int16?`（若可读到则保存）

  * `deviceId/deviceName: String?`（用于区分设备）

  * `source: String`（例如 bluetooth / manual）

* 同步与去重：扩展 [Persistence.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Persistence.swift) 中的 `CoreDataDeduplicator`：

  * `normalizeMissingIds` 增加 `BodyMeasurement`。

  * 追加 `dedupeBodyMeasurements`：优先按 `id` 去重；再按语义键（timestamp ± 容差 + weight + deviceId）合并重复。

* 可选：在保存一条 `BodyMeasurement` 后同步更新 `UserProfile.weight` 为最新体重（让个人信息页当前体重保持一致）。

## UI/交互（个人信息 Tab）

* 在 [PersonalInfoView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/PersonalInfo/PersonalInfoView.swift) 增加新的 Section：

  * 显示蓝牙状态（未授权/未开启/扫描中/已连接/读取中）。

  * “扫描并连接 S400”按钮 + 设备列表弹窗（选择设备后连接）。

  * 最近一次读数（体重、体脂、时间、来源：设备/估算）。

  * 最近 N 条历史记录列表（可先做简单列表；后续可加折线图）。

* 复用现有 `saveContext()` / `manualSync()` 入口：

  * 新记录入库后自动 `saveContext()`。

  * 用户仍可用“手动同步 iCloud 数据”触发去重与同步推进。

## 权限与工程配置

* 更新 [Info.plist](file:///Users/imac/Documents/Projects/MuscleMetric/Config/Info.plist) 增加：

  * `NSBluetoothAlwaysUsageDescription`（说明用于连接体脂秤同步体重体脂）。

  * 视最低 iOS 版本需要，补充 `NSBluetoothPeripheralUsageDescription` 作为兼容。

* 不默认开启后台蓝牙（`UIBackgroundModes=bluetooth-central`）以避免审核/耗电问题；如你希望“后台自动同步”，再追加该能力与对应交互开关。

## 验证与测试

* 添加纯 Swift 的解析单元测试：

  * Xiaomi 广播 payload 解析（稳定标记、单位换算、时间字段）。

  * GATT Measurement 解析（flags、体重单位、体脂字段）。

* 添加 Core Data 保存/去重测试（在 in-memory store 下）：

  * 重复记录（同 id/同语义键）最终只保留一条。

* 真机联调：iOS 模拟器无法使用蓝牙；需要在真机上用 S400 进行扫描/连接/上秤读取验证。

## 交付结果（你确认后我会直接开始实现）

* 个人信息 Tab 内可扫描连接 S400，读取体重/体脂（优先设备值，缺失则估算）并保存。

* 新增体重体脂历史记录，自动随 CloudKit 同步到 iCloud。

* 手动同步流程覆盖新实体，跨设备合并重复数据。

如你有两个偏好点我也会按“默认方案”先做：

* 默认只保存“稳定/最终”读数（避免上秤过程中的跳动数据写入）。

* 默认保存体重单位为 kg，UI 可扩展单位显示。

