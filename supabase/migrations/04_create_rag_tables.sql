-- ============================================================
-- Part 4: RAG知识库和审批审计表
-- ============================================================

-- 知识文档表
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

-- 创建向量索引
CREATE INDEX IF NOT EXISTS idx_knowledge_docs_embedding 
    ON public.knowledge_docs 
    USING ivfflat (embedding vector_cosine_ops) WITH (lists = 100);

-- 创建全文搜索索引
CREATE INDEX IF NOT EXISTS idx_knowledge_docs_search 
    ON public.knowledge_docs 
    USING gin(to_tsvector('chinese', title || ' ' || COALESCE(content, '')));

-- 审批记录
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

-- 审计日志
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

-- 创建审计日志索引
CREATE INDEX IF NOT EXISTS idx_audit_logs_trace ON public.audit_logs(trace_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity ON public.audit_logs(entity_type, entity_id);

-- 黄金样本表
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

SELECT 'Part 4 completed' as status;
