-- ============================================================
-- Part 6: 创建函数和触发器
-- ============================================================

-- 自动更新updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 为表添加触发器
DROP TRIGGER IF EXISTS update_customers_updated_at ON public.customers;
CREATE TRIGGER update_customers_updated_at 
    BEFORE UPDATE ON public.customers 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_opportunities_updated_at ON public.opportunities;
CREATE TRIGGER update_opportunities_updated_at 
    BEFORE UPDATE ON public.opportunities 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;
CREATE TRIGGER update_profiles_updated_at 
    BEFORE UPDATE ON public.profiles 
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- 商机状态变更审计
CREATE OR REPLACE FUNCTION log_opportunity_stage_change()
RETURNS TRIGGER AS $$
BEGIN
    IF OLD.current_stage IS DISTINCT FROM NEW.current_stage THEN
        INSERT INTO public.audit_logs (trace_id, entity_type, entity_id, action, performed_by, old_values, new_values)
        VALUES (
            COALESCE(NEW.id::text, gen_random_uuid()::text),
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

DROP TRIGGER IF EXISTS audit_opportunity_stage ON public.opportunities;
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

-- 验证所有表创建成功
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
ORDER BY table_name;
