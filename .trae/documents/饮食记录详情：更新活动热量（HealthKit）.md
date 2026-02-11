## 现状结论
- 「饮食记录详情」页的「活动热量」右侧确实已经有更新按钮，位置在 [DietRecordDetailView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/DietRecord/DietRecordDetailView.swift#L69-L90)。
- 但按钮点击所调用的 `refreshActiveEnergy()` 目前把 HealthKit 拉取逻辑整段注释掉了（等于不做任何事），所以不会更新数值：[DietRecordDetailView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/DietRecord/DietRecordDetailView.swift#L162-L179)。
- 同文件里其实已经写好了 HealthKit 查询封装 `HealthKitManager.fetchActiveEnergy(for:)`，用的是 `HKStatisticsQuery` + `.cumulativeSum` 来累计当天 `activeEnergyBurned`（单位 kcal）：[DietRecordDetailView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/DietRecord/DietRecordDetailView.swift#L262-L310)。

## 实现目标
- 点击更新按钮后：读取当前记录的日期（按本地时区的 00:00–24:00），从 HealthKit 获取当天“活动能量消耗”(Active Energy Burned) 的累计值，并写回 `DietRecord.activeEnergy`，同时保存到 Core Data。
- 处理不可用场景：模拟器/不支持设备（`isHealthDataAvailable == false`）、未授权/被拒绝、查询失败等，给用户明确提示。

## 需要补齐的工程能力
- Info.plist 已包含 HealthKit 读取权限文案（`NSHealthShareUsageDescription`/`NSHealthUpdateUsageDescription`），无需新增：[Info.plist](file:///Users/imac/Documents/Projects/MuscleMetric/Config/Info.plist#L25-L29)。
- 目前 entitlements 只有 iCloud/推送相关，没有 HealthKit entitlement，需要加上 `com.apple.developer.healthkit = true`（否则真机上授权/读取可能失败）：[MuscleMetric.entitlements](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/MuscleMetric.entitlements#L1-L17)。

## 具体改动步骤（将要做的代码修改）
1) 恢复并完善 `refreshActiveEnergy()`
- 去掉注释块，真正调用 `HealthKitManager.shared.requestAuthorization` → `fetchActiveEnergy`。
- 加入 `@State` 状态：`isRefreshingActiveEnergy`、`activeEnergyErrorMessage`、`showActiveEnergyErrorAlert`。
- 点击按钮时：
  - 先做设备可用性判断（HealthKit 不可用直接提示）。
  - 置 `isRefreshingActiveEnergy = true`，完成/失败后恢复。
  - 成功后在主线程赋值 `record.activeEnergy = energy` 并 `saveContext()`。
- UI 上：刷新中禁用按钮，并把图标替换为 `ProgressView()` 或保留图标但置灰（选一种一致的 SwiftUI 方式）。

2) 调整 onAppear 的自动刷新策略（避免反复弹授权）
- 现在 `onAppear` 里当 `activeEnergy == 0` 就自动调用刷新：[DietRecordDetailView.swift](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/Views/DietRecord/DietRecordDetailView.swift#L155-L159)。
- 我会改为“仅在已授权情况下才自动刷新”，未授权只让用户手动点按钮触发授权弹窗。
  - 实现方式：在 `HealthKitManager` 增加一个查询授权状态的方法（`authorizationStatus(for:)`），或用 `UserDefaults` 记录“是否已成功授权过”作兜底。

3) 增强 `HealthKitManager` 的健壮性
- 让 `fetchActiveEnergy` 在遇到 `error` 时能回传失败信息（现在丢弃了 error，只返回 nil）。
- 在授权失败/被拒绝时返回可展示的错误文案（例如“未授权读取健康数据，请在设置中开启”）。

4) 增加 HealthKit entitlement
- 在 [MuscleMetric.entitlements](file:///Users/imac/Documents/Projects/MuscleMetric/MuscleMetric/MuscleMetric.entitlements) 增加：
  - `com.apple.developer.healthkit` : `true`

## 验证方式
- 编译通过（Xcode build）。
- 真机运行：进入某天「饮食记录详情」→ 点击“更新” → 首次弹出 Health 授权 → 允许后应写入当天 kcal；再次进入同一天应可正常刷新且不重复弹授权。
- 模拟器运行：点击“更新”应提示“当前设备不支持 HealthKit/无法读取健康数据”，不会崩溃。

## 关键说明（关于“这个用户”）
- HealthKit 的活动能量是按“当前设备/Apple ID 的健康数据”聚合的，无法和应用内的 `UserProfile` 做一一绑定（除非你们额外做了多账号设备隔离/不同 Apple ID）。本次实现会以“当前设备的 Health 数据”作为来源，把结果写到当天记录里。