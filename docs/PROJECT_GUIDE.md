
# 🚀 CRM多Agent协同平台 - Supabase 集成部署指南

> 基于你的Supabase项目: `ebsndpzlfjeuojjkwycn`  
> GitHub仓库: `zhenxyy/CRM平台` (已连接)  
> 生产分支: `main`

---

## 📁 项目文件结构

```
crm-platform/
├── index.html                          # 主入口 (增强版v2.0)
├── README.md                           # 项目说明
├── config.js                           # Supabase配置 (GitHub Actions自动注入)
├── .env.local                          # 本地开发环境变量
├── .github/
│   └── workflows/
│       └── deploy.yml                  # GitHub Actions自动部署
├── supabase/
│   ├── config.toml                     # Supabase CLI配置
│   ├── functions/
│   │   ├── agent-orchestrator/         # Agent编排器
│   │   │   └── index.ts
│   │   ├── generate-embedding/         # Embedding生成
│   │   │   └── index.ts
│   │   ├── llm-agent/                  # LLM Agent路由
│   │   │   └── index.ts
│   │   └── cost-controller/            # 成本控制器
│   │       └── index.ts
│   └── migrations/
│       └── 001_initial_schema.sql      # 数据库初始架构
└── docs/
    ├── INTEGRATION_GUIDE.md            # 完整集成指南
    └── API_REFERENCE.md                # API参考文档
```

---

## ⚡ 快速开始 (5步完成部署)

### Step 1: 获取Supabase密钥

进入 [Supabase Dashboard](https://supabase.com/dashboard/project/ebsndpzlfjeuojjkwycn/settings/api)：

| 配置项 | 复制位置 | 用途 |
|--------|---------|------|
| `Project URL` | Project Settings → API → Project URL | 前端连接 |
| `anon public` | Project Settings → API → Project API keys | 匿名访问 |
| `service_role secret` | 同上，点击Reveal | Edge Functions |

### Step 2: 配置GitHub Secrets

进入你的GitHub仓库 `zhenxyy/CRM平台` → Settings → Secrets and variables → Actions → New repository secret：

| Secret Name | Value |
|-------------|-------|
| `SUPABASE_URL` | `https://ebsndpzlfjeuojjkwycn.supabase.co` |
| `SUPABASE_ANON_KEY` | 你的anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | 你的service_role key |
| `SUPABASE_ACCESS_TOKEN` | 从 [Supabase账户设置](https://supabase.com/dashboard/account/tokens) 生成 |
| `SUPABASE_DB_PASSWORD` | 数据库密码 (Database Settings → Database password) |
| `OPENAI_API_KEY` | 你的OpenAI API Key |

### Step 3: 初始化数据库

在Supabase Dashboard → SQL Editor → New query，执行 `supabase_schema.sql` 全部内容。

### Step 4: 推送代码到GitHub

```bash
# 克隆你的仓库
git clone https://github.com/zhenxyy/CRM平台.git
cd CRM平台

# 复制所有文件到仓库
cp /path/to/downloads/crm_multi_agent_platform_v2.html index.html
cp /path/to/downloads/README.md README.md
cp /path/to/downloads/supabase_schema.sql supabase/migrations/001_initial_schema.sql

# 创建GitHub Actions工作流
mkdir -p .github/workflows
cp /path/to/downloads/.github_workflows_deploy.yml .github/workflows/deploy.yml

# 创建Supabase配置
mkdir -p supabase/functions/agent-orchestrator
mkdir -p supabase/functions/generate-embedding
mkdir -p supabase/functions/llm-agent
mkdir -p supabase/functions/cost-controller

# 复制Edge Functions代码 (从supabase-edge-functions.ts中提取)
# ... (详见INTEGRATION_GUIDE.md)

# 提交并推送
git add .
git commit -m "feat: v2.0 + Supabase全栈集成

- 补齐8个Agent完整输出
- 添加人工接管边界案例
- 添加管理驾驶舱
- 添加产品路线图
- Supabase数据库集成
- Edge Functions部署
- GitHub Actions自动化"

git push origin main
```

### Step 5: 验证部署

1. 访问 `https://zhenxyy.github.io/CRM平台/`
2. 注册/登录账号
3. 提交一个客户资料
4. 在Supabase Dashboard → Table Editor 验证数据写入
5. 检查管理驾驶舱数据实时更新

---

## 🔧 核心功能已实现

### 前端 (index.html)
- ✅ 8个Agent完整输出展示
- ✅ 人工接管边界案例演示
- ✅ AI可信度评分可视化
- ✅ 管理驾驶舱 (团队级数据)
- ✅ 产品路线图 + 商业化定价
- ✅ 版本声明横幅

### 后端 (Supabase)
- ✅ 11张数据库表 (客户/商机/Agent运行/知识库/审批/审计等)
- ✅ pgvector向量搜索
- ✅ 行级安全 (RLS)
- ✅ 实时订阅 (Realtime)
- ✅ 4个Edge Functions

### 部署
- ✅ GitHub Pages静态托管
- ✅ GitHub Actions自动部署
- ✅ Supabase数据库自动迁移

---

## 🎯 面试亮点升级

现在你可以这样介绍项目：

> "我独立设计并落地了一个**CRM商机流转多Agent协同平台**，从前端交互到后端数据库到部署运维的**全栈产品**。
>
> **技术架构**：前端纯HTML+CSS+JS，后端Supabase (PostgreSQL + pgvector + Realtime)，4个Edge Functions处理Agent编排、Embedding生成、LLM路由、成本控制。
>
> **核心设计**：8个Agent覆盖商机全生命周期，RAG混合检索+重排序确保知识准确，MCP协议标准化工具调用，9项链路治理机制保障可靠性。
>
> **数据驱动**：所有Agent运行记录、商机状态变更、审批流程都实时写入数据库，管理层驾驶舱展示团队级漏斗转化率和Agent效能分析。
>
> **商业化思维**：设计了从Demo到SaaS到生态平台的三阶段路线图，包含试点验证方案、A/B测试设计、三档定价策略。"

---

## 📞 需要帮助？

- Supabase文档: https://supabase.com/docs
- 项目Dashboard: https://supabase.com/dashboard/project/ebsndpzlfjeuojjkwycn
- GitHub仓库: https://github.com/zhenxyy/CRM平台
