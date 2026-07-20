
-- ============================================================
-- CRM多Agent协同平台 - Supabase 数据库架构
-- 项目: ebsndpzlfjeuojjkwycn
-- 注意: 2026年5月30日后新建表需显式GRANT权限
-- ============================================================

-- 启用必要扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgvector";

-- ============================================================
-- 1. 用户与权限表 (基于Supabase Auth扩展)
-- ============================================================

-- 用户角色枚举类型
CREATE TYPE user_role AS ENUM ('sales_rep', 'sales_manager', 'admin', 'csm');

-- 用户资料表 (关联Supabase Auth users)
CREATE TABLE public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role user_role DEFAULT 'sales_rep',
    team_id UUID,
    monthly_token_budget DECIMAL(10,2) DEFAULT 50.00,
    token_used_this_month DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 团队表
CREATE TABLE public.teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    manager_id UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 添加team_id外键
ALTER TABLE public.profiles 
    ADD CONSTRAINT fk_profiles_team 
    FOREIGN KEY (team_id) REFERENCES public.teams(id);

-- ============================================================
-- 2. 客户与商机核心表
-- ============================================================

-- 客户表
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    company_name TEXT NOT NULL,
    industry TEXT,
    contact_info JSONB DEFAULT '{}',
    source TEXT,
    assigned_to UUID REFERENCES public.profiles(id),
    team_id UUID REFERENCES public.teams(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 商机表 (核心)
CREATE TABLE public.opportunities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    title TEXT NOT NULL,

    -- 评级结果
    lead_score INTEGER CHECK (lead_score >= 0 AND lead_score <= 100),
    lead_grade TEXT CHECK (lead_grade IN ('S', 'A', 'B', 'C', 'D', 'HOLD')),
    scenario_type TEXT,

    -- 商机状态机
    current_stage TEXT DEFAULT 'NEW' CHECK (
        current_stage IN ('NEW', 'SCORED', 'PROFILING', 'PLANNED', 'EXECUTING', 'QA_PASSED', 'APPROVED', 'WON', 'LOST', 'HOLD')
    ),

    -- 预算与预期
    budget_range TEXT,
    expected_close_date DATE,
    estimated_value DECIMAL(12,2),

    -- AI可信度
    ai_confidence DECIMAL(3,2) CHECK (ai_confidence >= 0 AND ai_confidence <= 1),
    requires_human BOOLEAN DEFAULT FALSE,

    -- 归属
    owner_id UUID REFERENCES public.profiles(id),
    team_id UUID REFERENCES public.teams(id),

    -- 时间戳
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 3. Agent输出数据表
-- ============================================================

-- Agent运行记录
CREATE TABLE public.agent_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    agent_name TEXT NOT NULL CHECK (agent_name IN (
        'lead_scoring', 'customer_profiling', 'knowledge_retrieval', 
        'task_planning', 'tool_execution', 'quality_assurance', 
        'approval_guard', 'crm_writeback'
    )),

    -- 输入输出哈希 (用于审计)
    input_hash TEXT,
    output_hash TEXT,

    -- 执行指标
    status TEXT DEFAULT 'running' CHECK (status IN ('running', 'success', 'failed', 'timeout')),
    latency_ms INTEGER,
    token_count INTEGER,
    cost_usd DECIMAL(8,4),

    -- 输出内容 (JSON结构化)
    output_data JSONB DEFAULT '{}',
    confidence DECIMAL(3,2),

    -- 错误信息
    error_message TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 客户画像数据
CREATE TABLE public.customer_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,

    -- 画像内容
    profile_data JSONB DEFAULT '{}',
    decision_chain JSONB DEFAULT '[]',
    risk_signals JSONB DEFAULT '[]',
    upsell_probability DECIMAL(3,2),

    -- 关联历史
    similar_opportunities JSONB DEFAULT '[]',

    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 任务规划数据
CREATE TABLE public.task_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,

    tasks JSONB DEFAULT '[]',
    total_duration_days INTEGER,
    dependencies JSONB DEFAULT '[]',

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 工具执行日志
CREATE TABLE public.tool_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    agent_run_id UUID REFERENCES public.agent_runs(id),

    tool_name TEXT NOT NULL,
    tool_params JSONB DEFAULT '{}',
    execution_result JSONB DEFAULT '{}',
    execution_time_ms INTEGER,
    status TEXT DEFAULT 'success' CHECK (status IN ('success', 'failed', 'retrying')),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 4. RAG知识库表
-- ============================================================

-- 知识文档表
CREATE TABLE public.knowledge_docs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    doc_type TEXT CHECK (doc_type IN ('product', 'case_study', 'competitor', 'faq', 'whitepaper', 'best_practice')),
    industry_tags TEXT[] DEFAULT '{}',
    source_url TEXT,

    -- 向量嵌入 (使用pgvector)
    embedding VECTOR(1024),

    -- 元数据
    metadata JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建向量索引 (IVFFlat, 适合中等规模)
CREATE INDEX idx_knowledge_docs_embedding ON public.knowledge_docs 
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- 创建全文搜索索引
CREATE INDEX idx_knowledge_docs_search ON public.knowledge_docs 
    USING gin(to_tsvector('chinese', title || ' ' || COALESCE(content, '')));

-- ============================================================
-- 5. 审批与审计表
-- ============================================================

-- 审批记录
CREATE TABLE public.approvals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,

    approval_type TEXT NOT NULL CHECK (approval_type IN ('discount', 'contract_change', 'customer_transfer', 'custom_dev')),
    requested_by UUID REFERENCES public.profiles(id),

    -- 审批链
    approval_chain JSONB DEFAULT '[]',
    current_approver UUID REFERENCES public.profiles(id),

    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'escalated')),

    -- 支撑材料
    supporting_docs JSONB DEFAULT '[]',
    risk_analysis TEXT,

    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

-- 审计日志
CREATE TABLE public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trace_id TEXT NOT NULL,

    entity_type TEXT NOT NULL CHECK (entity_type IN ('opportunity', 'customer', 'approval', 'agent_run')),
    entity_id UUID,

    action TEXT NOT NULL,
    performed_by UUID REFERENCES public.profiles(id),

    old_values JSONB DEFAULT '{}',
    new_values JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 创建审计日志索引
CREATE INDEX idx_audit_logs_trace ON public.audit_logs(trace_id);
CREATE INDEX idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);

-- ============================================================
-- 6. 黄金样本表
-- ============================================================

CREATE TABLE public.golden_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sample_id TEXT UNIQUE NOT NULL,

    -- 分类
    scenario TEXT NOT NULL CHECK (scenario IN ('new_customer', 'upsell', 'competitor_replace', 'renewal', 'winback')),
    agent_focus TEXT,
    is_boundary_case BOOLEAN DEFAULT FALSE,

    -- 样本内容
    input_context JSONB NOT NULL,
    expected_agent_chain TEXT[] DEFAULT '{}',
    expected_output JSONB NOT NULL,
    expected_crm_fields JSONB DEFAULT '{}',

    -- 测试状态
    test_status TEXT DEFAULT 'active' CHECK (test_status IN ('active', 'deprecated', 'draft')),
    last_tested_at TIMESTAMPTZ,
    pass_rate DECIMAL(4,2),

    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- 7. 启用行级安全 (RLS)
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.agent_runs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.task_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.tool_executions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- RLS策略: 用户只能查看自己团队的数据
CREATE POLICY "team_isolation_customers" ON public.customers
    FOR ALL USING (team_id IN (
        SELECT team_id FROM public.profiles WHERE id = auth.uid()
    ));

CREATE POLICY "team_isolation_opportunities" ON public.opportunities
    FOR ALL USING (team_id IN (
        SELECT team_id FROM public.profiles WHERE id = auth.uid()
    ));

CREATE POLICY "own_profile" ON public.profiles
    FOR ALL USING (id = auth.uid());

-- 管理员可以查看所有数据
CREATE POLICY "admin_full_access" ON public.opportunities
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    );

-- ============================================================
-- 8. 设置权限 (GRANT) - 2026年5月30日后新建表必需
-- ============================================================

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- 为 future tables 设置默认权限
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public 
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO anon;

-- ============================================================
-- 9. 创建函数和触发器
-- ============================================================

-- 自动更新 updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_customers_updated_at 
    BEFORE UPDATE ON public.customers 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_opportunities_updated_at 
    BEFORE UPDATE ON public.opportunities 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 商机状态变更时记录审计日志
CREATE OR REPLACE FUNCTION log_opportunity_stage_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.current_stage IS DISTINCT FROM NEW.current_stage THEN
        INSERT INTO public.audit_logs (trace_id, entity_type, entity_id, action, performed_by, old_values, new_values)
        VALUES (
            COALESCE(NEW.trace_id, gen_random_uuid()::text),
            'opportunity',
            NEW.id,
            'stage_change',
            auth.uid(),
            jsonb_build_object('stage', OLD.current_stage),
            jsonb_build_object('stage', NEW.current_stage)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_opportunity_stage 
    AFTER UPDATE ON public.opportunities 
    FOR EACH ROW EXECUTE FUNCTION log_opportunity_stage_change();

-- 向量相似度搜索函数
CREATE OR REPLACE FUNCTION match_knowledge_docs(
    query_embedding VECTOR(1024),
    match_threshold FLOAT,
    match_count INT,
    p_industry_tags TEXT[] DEFAULT '{}'
)
RETURNS TABLE (
    id UUID,
    title TEXT,
    content TEXT,
    doc_type TEXT,
    similarity FLOAT
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        kd.id,
        kd.title,
        kd.content,
        kd.doc_type,
        1 - (kd.embedding <=> query_embedding) AS similarity
    FROM public.knowledge_docs kd
    WHERE 
        1 - (kd.embedding <=> query_embedding) > match_threshold
        AND (p_industry_tags = '{}' OR kd.industry_tags && p_industry_tags)
    ORDER BY kd.embedding <=> query_embedding
    LIMIT match_count;
END;
$$ LANGUAGE plpgsql;
