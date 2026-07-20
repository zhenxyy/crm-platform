
# CRM多Agent协同平台 - Supabase 集成指南

> 项目地址: https://supabase.com/dashboard/project/ebsndpzlfjeuojjkwycn

---

## 📋 前置准备

### 1. 获取Supabase连接信息

进入 [Supabase Dashboard](https://supabase.com/dashboard/project/ebsndpzlfjeuojjkwycn/settings/api)，获取以下信息：

| 配置项 | 位置 | 用途 |
|--------|------|------|
| `Project URL` | Project Settings → API → Project URL | 前端连接 |
| `anon public` | Project Settings → API → Project API keys | 匿名用户访问 |
| `service_role secret` | Project Settings → API → Project API keys | Edge Functions管理员权限 |

### 2. 安装Supabase CLI (本地开发)

```bash
# macOS
brew install supabase/tap/supabase

# Windows (scoop)
scoop bucket add supabase https://github.com/supabase/scoop-bucket.git
scoop install supabase

# 登录
supabase login
```

---

## 🗄️ 第一步：初始化数据库

### 1.1 执行SQL建表

在Supabase Dashboard中：
1. 进入 **SQL Editor** → **New query**
2. 复制 `supabase_schema.sql` 全部内容
3. 点击 **Run**

### 1.2 验证表创建成功

```sql
-- 检查所有表
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;

-- 预期结果:
-- agent_runs
-- approvals
-- audit_logs
-- customers
-- customer_profiles
-- golden_samples
-- knowledge_docs
-- opportunities
-- profiles
-- task_plans
-- teams
-- tool_executions
```

### 1.3 创建初始数据

```sql
-- 创建示例团队
INSERT INTO public.teams (name) VALUES 
    ('华东销售一部'),
    ('华北销售二部');

-- 创建示例知识文档 (带向量嵌入)
INSERT INTO public.knowledge_docs (title, content, doc_type, industry_tags, embedding)
VALUES (
    '飞书企业版安全白皮书',
    '飞书企业版已通过等保三级认证，支持私有化部署...',
    'whitepaper',
    ARRAY['互联网', '金融'],
    ARRAY[0.1, 0.2, ...]::vector(1024)  -- 实际应通过Embedding API生成
);
```

---

## 🔌 第二步：前端集成

### 2.1 在HTML中引入Supabase

在 `index.html` 的 `<head>` 中添加：

```html
<!-- Supabase JS SDK -->
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

<!-- 你的Supabase客户端代码 -->
<script src="supabase-client.js"></script>
```

### 2.2 修改提交逻辑，接入真实数据库

找到原有的 `submitMaterials` 函数，替换为：

```javascript
async function submitMaterials() {
    const form = document.getElementById('submitForm');

    // 1. 创建客户和商机 (写入Supabase)
    const { customer, opportunity } = await CRMSupabase.opportunities.create({
        customerName: form.customerName.value,
        companyName: form.companyName.value,
        industry: form.industry.value,
        contact: form.contact.value,
        source: form.source.value,
        budget: form.budget.value,
        timeline: form.timeline.value,
        requirements: form.requirements.value
    });

    // 2. 显示结果面板
    document.getElementById('resultPanel').classList.remove('hidden');

    // 3. 调用Edge Function执行Agent链
    const response = await fetch(
        'https://ebsndpzlfjeuojjkwycn.supabase.co/functions/v1/agent-orchestrator',
        {
            method: 'POST',
            headers: {
                'Authorization': `Bearer ${(await supabase.auth.getSession()).data.session.access_token}`,
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ opportunity_id: opportunity.id })
        }
    );

    const { results } = await response.json();

    // 4. 实时订阅Agent运行状态
    const channel = CRMSupabase.realtime.subscribeAgentRuns(
        opportunity.id,
        (newRun) => {
            // 新Agent运行记录到达，更新UI
            updateAgentOutput(newRun);
        }
    );

    // 5. 最终评级展示
    const { data: finalOpp } = await CRMSupabase.opportunities.getById(opportunity.id);
    showRating(finalOpp);
}
```

### 2.3 实时更新管理驾驶舱

```javascript
// 在管理驾驶舱页面初始化时
const dashboardChannel = CRMSupabase.realtime.subscribeOpportunities((payload) => {
    // 商机数据变化时自动刷新驾驶舱
    if (payload.eventType === 'INSERT' || payload.eventType === 'UPDATE') {
        refreshDashboard();
    }
});

// 页面卸载时取消订阅
window.addEventListener('beforeunload', () => {
    CRMSupabase.realtime.unsubscribe(dashboardChannel);
});
```

---

## ⚡ 第三步：部署Edge Functions

### 3.1 初始化本地项目

```bash
# 在项目目录中
supabase init
supabase link --project-ref ebsndpzlfjeuojjkwycn
```

### 3.2 创建Functions

```bash
# 创建Agent编排器
supabase functions new agent-orchestrator

# 创建Embedding生成器
supabase functions new generate-embedding

# 创建LLM Agent路由
supabase functions new llm-agent

# 创建成本控制器
supabase functions new cost-controller
```

### 3.3 复制代码到对应文件

将 `supabase-edge-functions.ts` 中的代码分别复制到：
- `supabase/functions/agent-orchestrator/index.ts`
- `supabase/functions/generate-embedding/index.ts`
- `supabase/functions/llm-agent/index.ts`
- `supabase/functions/cost-controller/index.ts`

### 3.4 设置环境变量

```bash
# 设置OpenAI API Key
supabase secrets set OPENAI_API_KEY=sk-your-key

# 设置其他密钥
supabase secrets set SUPABASE_URL=https://ebsndpzlfjeuojjkwycn.supabase.co
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
```

### 3.5 部署

```bash
supabase functions deploy

# 部署单个Function
supabase functions deploy agent-orchestrator
```

---

## 🔐 第四步：配置RLS和权限

### 4.1 验证RLS策略

在SQL Editor中执行：

```sql
-- 检查RLS是否启用
SELECT relname, relrowsecurity 
FROM pg_class 
WHERE relname IN ('opportunities', 'customers', 'agent_runs');

-- 预期: relrowsecurity = true
```

### 4.2 测试权限隔离

```sql
-- 以不同用户身份测试
SET LOCAL ROLE authenticated;

-- 应该只能看到本团队数据
SELECT * FROM public.opportunities;
```

---

## 📊 第五步：验证完整流程

### 5.1 端到端测试

1. 打开网站，登录账号
2. 点击"提交资料"，填写客户信息
3. 观察数据是否写入Supabase
4. 检查Agent运行记录是否生成
5. 验证管理驾驶舱数据更新

### 5.2 检查数据一致性

```sql
-- 检查商机和Agent运行记录
SELECT 
    o.id,
    o.title,
    o.lead_grade,
    o.current_stage,
    COUNT(ar.id) as agent_runs,
    SUM(ar.cost_usd) as total_cost
FROM public.opportunities o
LEFT JOIN public.agent_runs ar ON o.id = ar.opportunity_id
GROUP BY o.id;
```

---

## 🚀 第六步：GitHub Pages + Supabase 完整部署

### 6.1 更新GitHub Actions

创建 `.github/workflows/deploy.yml`：

```yaml
name: Deploy to GitHub Pages

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: '20'

      - name: Inject Supabase Config
        run: |
          echo "window.SUPABASE_CONFIG = {" >> index.html
          echo "  url: '${{ secrets.SUPABASE_URL }}'," >> index.html
          echo "  anonKey: '${{ secrets.SUPABASE_ANON_KEY }}'" >> index.html
          echo "};" >> index.html

      - name: Deploy to GitHub Pages
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./
```

### 6.2 在GitHub仓库设置Secrets

进入仓库 Settings → Secrets and variables → Actions：

| Secret Name | Value |
|-------------|-------|
| `SUPABASE_URL` | `https://ebsndpzlfjeuojjkwycn.supabase.co` |
| `SUPABASE_ANON_KEY` | 你的anon key |

---

## 🛠️ 常见问题

### Q: 前端报错 "permission denied for table opportunities"

**A**: 2026年5月30日后新建表需显式GRANT：
```sql
GRANT SELECT, INSERT, UPDATE, DELETE ON public.opportunities TO authenticated;
```

### Q: Edge Function调用返回 401

**A**: 确保请求头中包含有效的JWT Token：
```javascript
headers: {
    'Authorization': `Bearer ${session.access_token}`
}
```

### Q: 向量搜索返回空结果

**A**: 检查embedding维度是否匹配 (1024)，以及是否创建了ivfflat索引。

### Q: Realtime订阅不生效

**A**: 在Supabase Dashboard → Database → Replication 中确认启用了Realtime。

---

## 📚 参考文档

- [Supabase JS SDK文档](https://supabase.com/docs/reference/javascript)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Row Level Security](https://supabase.com/docs/guides/auth/row-level-security)
- [Realtime订阅](https://supabase.com/docs/guides/realtime)
- [pgvector向量搜索](https://supabase.com/docs/guides/ai)
