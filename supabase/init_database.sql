-- CRM多Agent协同平台 - 数据库初始化
-- 项目: ebsndpzlfjeuojjkwycn
-- 执行方式: 复制全部内容 → Supabase SQL Editor → New query → Run

-- ============================================================
-- STEP 1: 启用扩展
-- ============================================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "vector";

-- ============================================================
-- STEP 2: 创建枚举类型
-- ============================================================
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('sales_rep', 'sales_manager', 'admin', 'csm');
    END IF;
END $$;

-- ============================================================
-- STEP 3: 创建基础表
-- ============================================================

CREATE TABLE IF NOT EXISTS public.teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    manager_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT,
    role user_role DEFAULT 'sales_rep',
    team_id UUID REFERENCES public.teams(id),
    monthly_token_budget DECIMAL(10,2) DEFAULT 50.00,
    token_used_this_month DECIMAL(10,2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.teams ADD CONSTRAINT fk_teams_manager FOREIGN KEY (manager_id) REFERENCES public.profiles(id);

CREATE TABLE IF NOT EXISTS public.customers (
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

CREATE TABLE IF NOT EXISTS public.opportunities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    lead_score INTEGER CHECK (lead_score >= 0 AND lead_score <= 100),
    lead_grade TEXT CHECK (lead_grade IN ('S', 'A', 'B', 'C', 'D', 'HOLD')),
    scenario_type TEXT,
    current_stage TEXT DEFAULT 'NEW',
    budget_range TEXT,
    expected_close_date DATE,
    estimated_value DECIMAL(12,2),
    ai_confidence DECIMAL(3,2),
    requires_human BOOLEAN DEFAULT FALSE,
    owner_id UUID REFERENCES public.profiles(id),
    team_id UUID REFERENCES public.teams(id),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- STEP 4: 创建Agent相关表
-- ============================================================

CREATE TABLE IF NOT EXISTS public.agent_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    agent_name TEXT NOT NULL,
    status TEXT DEFAULT 'running',
    latency_ms INTEGER,
    token_count INTEGER,
    cost_usd DECIMAL(8,4),
    output_data JSONB DEFAULT '{}',
    confidence DECIMAL(3,2),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.customer_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    profile_data JSONB DEFAULT '{}',
    decision_chain JSONB DEFAULT '[]',
    risk_signals JSONB DEFAULT '[]',
    upsell_probability DECIMAL(3,2),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.task_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    tasks JSONB DEFAULT '[]',
    total_duration_days INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.tool_executions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    agent_run_id UUID REFERENCES public.agent_runs(id),
    tool_name TEXT NOT NULL,
    tool_params JSONB DEFAULT '{}',
    execution_result JSONB DEFAULT '{}',
    execution_time_ms INTEGER,
    status TEXT DEFAULT 'success',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- STEP 5: 创建RAG知识库和审批审计表
-- ============================================================

CREATE TABLE IF NOT EXISTS public.knowledge_docs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    doc_type TEXT,
    industry_tags TEXT[] DEFAULT '{}',
    source_url TEXT,
    embedding VECTOR(1024),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_knowledge_docs_embedding ON public.knowledge_docs 
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

CREATE TABLE IF NOT EXISTS public.approvals (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    approval_type TEXT NOT NULL,
    requested_by UUID REFERENCES public.profiles(id),
    approval_chain JSONB DEFAULT '[]',
    current_approver UUID REFERENCES public.profiles(id),
    status TEXT DEFAULT 'pending',
    supporting_docs JSONB DEFAULT '[]',
    risk_analysis TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    trace_id TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id UUID,
    action TEXT NOT NULL,
    performed_by UUID REFERENCES public.profiles(id),
    old_values JSONB DEFAULT '{}',
    new_values JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_trace ON public.audit_logs(trace_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);

CREATE TABLE IF NOT EXISTS public.golden_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sample_id TEXT UNIQUE NOT NULL,
    scenario TEXT NOT NULL,
    agent_focus TEXT,
    is_boundary_case BOOLEAN DEFAULT FALSE,
    input_context JSONB NOT NULL,
    expected_agent_chain TEXT[] DEFAULT '{}',
    expected_output JSONB NOT NULL,
    expected_crm_fields JSONB DEFAULT '{}',
    test_status TEXT DEFAULT 'active',
    last_tested_at TIMESTAMPTZ,
    pass_rate DECIMAL(4,2),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
-- STEP 6: 启用RLS
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

CREATE POLICY "admin_full_access" ON public.opportunities
    FOR ALL USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    );

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO anon;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;

-- ============================================================
-- STEP 7: 创建函数和触发器
-- ============================================================

CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_customers_updated_at BEFORE UPDATE ON public.customers 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_opportunities_updated_at BEFORE UPDATE ON public.opportunities 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE OR REPLACE FUNCTION log_opportunity_stage_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.current_stage IS DISTINCT FROM NEW.current_stage THEN
        INSERT INTO public.audit_logs (trace_id, entity_type, entity_id, action, performed_by, old_values, new_values)
        VALUES (
            COALESCE(NEW.id::text, gen_random_uuid()::text),
            'opportunity', NEW.id, 'stage_change', auth.uid(),
            jsonb_build_object('stage', OLD.current_stage),
            jsonb_build_object('stage', NEW.current_stage)
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER audit_opportunity_stage AFTER UPDATE ON public.opportunities 
    FOR EACH ROW EXECUTE FUNCTION log_opportunity_stage_change();

CREATE OR REPLACE FUNCTION match_knowledge_docs(
    query_embedding VECTOR(1024),
    match_threshold FLOAT,
    match_count INT,
    p_industry_tags TEXT[] DEFAULT '{}'
)
RETURNS TABLE (id UUID, title TEXT, content TEXT, doc_type TEXT, similarity FLOAT) AS $$
BEGIN
    RETURN QUERY
    SELECT kd.id, kd.title, kd.content, kd.doc_type,
        1 - (kd.embedding <=> query_embedding) AS similarity
    FROM public.knowledge_docs kd
    WHERE 1 - (kd.embedding <=> query_embedding) > match_threshold
        AND (p_industry_tags = '{}' OR kd.industry_tags && p_industry_tags)
    ORDER BY kd.embedding <=> query_embedding
    LIMIT match_count;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 验证
-- ============================================================
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' ORDER BY table_name;
