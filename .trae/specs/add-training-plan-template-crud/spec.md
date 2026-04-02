# 训练计划模板完整展示与增删改查 Spec

## Why
当前训练计划模板仅支持部分字段展示与导入后的浏览，无法在 App 内对训练计划模板进行完整查看与增删改查，影响用户实际维护计划的效率。

## What Changes
- 在训练计划相关页面中，**完整展示**训练计划模板的字段（计划信息、训练日、动作明细）。
- 为训练计划模板增加 **CRUD**：新建/查看/编辑/删除（含训练日与训练动作的增删改查）。
- 训练计划模板仍以 **iCloud 文件（JSON）** 作为唯一数据源，编辑后的结果写回 iCloud。
- **非目标**：本次不改动训练记录（训练日记录/动作记录）的结构与逻辑，仅保证其能继续读取被编辑后的模板字段用于展示/新建记录。

## Impact
- Affected specs: 训练计划模板管理、训练日详情展示、计划导入/导出
- Affected code:
  - `MuscleMetric/ContentView.swift`（现有训练计划相关视图与存储逻辑）
  - iCloud 目录：`Documents/TrainingPlans/`（计划文件），`Documents/TrainingPlans/Exports/`（导出文件）

## ADDED Requirements
### Requirement: 训练计划模板完整展示
系统 SHALL 在训练计划模板详情与训练日模板详情中展示完整字段。

#### Scenario: 查看计划模板
- **WHEN** 用户打开“选择训练计划”中的某个计划详情
- **THEN** 页面展示计划名、训练日列表；每个训练日可查看 title、tips

#### Scenario: 查看训练日模板详情
- **WHEN** 用户打开某个训练日模板详情
- **THEN** 页面展示 tips（可见/可展开）与训练动作列表
- **AND** 每个训练动作展示 name、rep、set、rest（默认可折叠，但必须能展开查看全部字段）

### Requirement: 训练计划模板新增（Create）
系统 SHALL 允许用户在 App 内新建训练计划模板并保存到 iCloud。

#### Scenario: 新建计划
- **WHEN** 用户在“选择训练计划”页面点击“新建计划”
- **THEN** 进入新建页面，用户可输入计划名称并保存
- **AND** 保存后计划出现在列表中，且对应 JSON 文件写入 iCloud `Documents/TrainingPlans/`

#### Scenario: 新建训练日与动作
- **WHEN** 用户在计划编辑界面新增训练日或新增训练动作
- **THEN** 新增项立即出现在 UI 中，并在保存后写入计划 JSON

### Requirement: 训练计划模板编辑（Update）
系统 SHALL 允许用户编辑计划模板字段并写回 iCloud 文件。

#### Scenario: 编辑计划名称
- **WHEN** 用户编辑计划名称并点击保存
- **THEN** 列表与详情立即反映新名称
- **AND** iCloud 中该计划的 JSON 内容被更新（同一 plan id 文件覆盖写入）

#### Scenario: 编辑训练日与动作字段
- **WHEN** 用户编辑训练日 title/tips 或训练动作的 name/rep/set/rest 并保存
- **THEN** 模板详情展示更新后的内容
- **AND** 后续通过“开始训练”新建训练记录时，生成的动作基础信息使用更新后的字段

### Requirement: 训练计划模板删除（Delete）
系统 SHALL 允许用户删除训练计划模板并同步删除 iCloud 文件。

#### Scenario: 删除计划
- **WHEN** 用户在列表中对计划执行删除操作并确认
- **THEN** 该计划从列表消失
- **AND** 对应 iCloud JSON 文件被删除
- **AND** 若当前已选择的计划被删除，系统应清空当前选择并回退为“选择计划”状态

### Requirement: 训练计划模板查询（Read/List/Search）
系统 SHALL 提供可浏览的计划列表并支持基础查找能力。

#### Scenario: 列表浏览
- **WHEN** 用户进入“选择训练计划”
- **THEN** 展示 iCloud 中所有计划模板（按更新时间倒序）

#### Scenario: 按名称查找
- **WHEN** 用户输入关键字
- **THEN** 列表按计划名称过滤显示匹配项（大小写不敏感）

### Requirement: 训练计划模板导出（Export）
系统 SHALL 支持导出单个训练计划模板为 JSON 文件并保存到 iCloud，同时可分享。

#### Scenario: 导出模板 JSON
- **WHEN** 用户在训练计划页对当前选中计划点击“导出”
- **THEN** 生成导出文件写入 iCloud `Documents/TrainingPlans/Exports/`
- **AND** 弹出系统分享面板

## MODIFIED Requirements
### Requirement: 训练计划模板存储模型
系统 SHALL 保持“计划模板 = iCloud JSON 文件”的存储方式不变，并支持覆盖写入更新。

#### Scenario: 覆盖写入
- **WHEN** 用户编辑并保存一个已有 plan id 的计划
- **THEN** 保存逻辑覆盖写入对应 `training_plan_<id>.json`

### Requirement: 开始训练依赖模板
系统 SHALL 在“开始训练 → 新建训练记录”生成动作基础信息时，读取当前模板字段（name/rep/set/rest）并写入训练记录条目。

## REMOVED Requirements
（无）

