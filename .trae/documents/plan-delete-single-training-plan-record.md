# 新增删除单条训练计划记录功能 — 实施计划

## 目标
在「训练计划」Tab 的训练记录列表中，支持删除单条训练计划记录（TrainingRecord），删除后列表即时更新，并且通过 CoreData/CloudKit 同步到 iCloud。

## 现状定位（只读）
- 训练计划记录列表位于 `PlanTrainingRecordListView`（当前按 `planId` 过滤展示 TrainingRecord）。
- 每条记录点击进入 `PlanTrainingRecordDetailView`（展示动作列表）。

## 方案概述
在训练记录列表（PlanTrainingRecordListView）为每条记录增加“删除”入口（建议使用右滑删除），并在删除时：
1. 执行 `viewContext.delete(record)`；
2. `try viewContext.save()` 持久化；
3. 列表依赖 `@FetchRequest` 自动刷新；
4. 由于 `TrainingRecord.entries` 关系为 Cascade，记录删除会级联删除对应的训练动作记录（TrainingEntry）。

## 实施步骤
1. **代码定位与结构确认**
   - 打开 `ContentView.swift`，确认 `PlanTrainingRecordListView` 的 `List/ForEach(records)` 结构与当前导航逻辑。
   - 确认 CoreData 模型里 `TrainingRecord.entries` 的删除规则为 Cascade（已存在则仅确认）。

2. **增加删除入口（列表）**
   - 在 `ForEach(records)` 的 row 上添加 `swipeActions`：
     - `Button(role: .destructive) { ... } label: { Text("删除") }`
   - 可选：为避免误删，增加 `confirmationDialog` 二次确认；若不需要确认则直接删除。

3. **实现删除逻辑（持久化 + 刷新）**
   - 在 `PlanTrainingRecordListView` 内新增私有方法 `deleteRecord(_ record: TrainingRecord)`：
     - `viewContext.delete(record)`
     - `try viewContext.save()`（失败时展示 alert）
   - 确保删除后不会崩溃：避免在 UI 仍引用已删除对象（删除时不在详情页；如果允许在详情页删除，则需要 dismiss 并处理导航）。

4. **（可选增强）详情页删除**
   - 若你希望在 `PlanTrainingRecordDetailView` 里也能删除：
     - 在 toolbar 添加“删除”按钮
     - 删除后 `dismiss()` 回列表，并保存 context

5. **验证**
   - 构建通过（iOS Simulator）。
   - 手动验证：
     - 创建若干训练计划记录
     - 在列表右滑删除其中一条 → 立刻从列表消失
     - 重新进入训练计划页 → 记录仍已删除
     - 如已开启 iCloud/CloudKit，同步后其他设备不再出现该记录（可作为补充验证）

## 影响范围
- 主要影响文件：`MuscleMetric/ContentView.swift`
- 不涉及数据模型变更（复用既有 TrainingRecord/TrainingEntry）。

## 风险与回避
- **误删**：可用 `confirmationDialog` 降低误操作。
- **已在详情页时删除**：若实现详情页删除，需要先 dismiss，避免已删除对象仍被渲染。

