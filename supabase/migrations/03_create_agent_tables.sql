-- ============================================================
-- Part 3: Agent相关表
-- ============================================================

-- Agent运行记录
CREATE TABLE IF NOT EXISTS public.agent_runs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    agent_name TEXT NOT NULL,
    input_hash TEXT,
    output_hash TEXT,
    status TEXT DEFAULT 'running',
    latency_ms INTEGER,
    token_count INTEGER,
    cost_usd DECIMAL(8,4),
    output_data JSONB DEFAULT '{}',
    confidence DECIMAL(3,2),
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 客户画像数据
CREATE TABLE IF NOT EXISTS public.customer_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    customer_id UUID REFERENCES public.customers(id) ON DELETE CASCADE,
    profile_data JSONB DEFAULT '{}',
    decision_chain JSONB DEFAULT '[]',
    risk_signals JSONB DEFAULT '[]',
    upsell_probability DECIMAL(3,2),
    similar_opportunities JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 任务规划数据
CREATE TABLE IF NOT EXISTS public.task_plans (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    opportunity_id UUID REFERENCES public.opportunities(id) ON DELETE CASCADE,
    tasks JSONB DEFAULT '[]',
    total_duration_days INTEGER,
    dependencies JSONB DEFAULT '[]',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 工具执行日志
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

SELECT 'Part 3 completed' as status;
