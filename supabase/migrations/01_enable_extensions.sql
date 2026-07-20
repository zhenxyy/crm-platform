-- ============================================================
-- Part 1: 启用扩展
-- 在Supabase Dashboard → SQL Editor中单独执行此部分
-- ============================================================

-- 启用UUID扩展
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 启用pgvector扩展 (Supabase已内置，只需启用)
CREATE EXTENSION IF NOT EXISTS "vector";

-- 验证扩展是否启用
SELECT extname, extversion FROM pg_extension WHERE extname IN ('uuid-ossp', 'vector');
