# Tasks
- [x] Task 1: 补齐训练计划模板详情的完整字段展示
  - [x] 在计划详情页展示计划基础信息与训练日 tips
  - [x] 在训练日模板详情页展示动作的 name/rep/set/rest（支持折叠/展开但可完整查看）

- [x] Task 2: 实现训练计划模板 CRUD（计划/训练日/训练动作）
  - [x] 新建计划：生成 plan id、默认空 days，保存为 iCloud JSON 文件
  - [x] 编辑计划：编辑 name；编辑训练日 title/tips；编辑动作 name/rep/set/rest；保存覆盖写入
  - [x] 删除计划：删除 iCloud JSON 文件；若删除当前计划则清空选择

- [x] Task 3: 实现训练计划模板列表查找
  - [x] 在“选择训练计划”页增加关键字过滤（按名称）

- [x] Task 4: 增加训练计划模板导出能力
  - [x] 在训练计划页提供导出入口并生成模板导出 JSON（单计划）
  - [x] 导出文件写入 iCloud `Documents/TrainingPlans/Exports/` 并支持分享

- [x] Task 5: 验证与回归
  - [x] 验证：新增/编辑/删除模板后，重新进入页面仍为最新内容（iCloud 文件持久化）
  - [x] 回归：开始训练生成的动作信息与模板一致
  - [x] 运行编译与基础手动验证

# Task Dependencies
- Task 2 依赖 Task 1（编辑/保存需要明确字段展示结构）
- Task 4 可与 Task 3 并行
