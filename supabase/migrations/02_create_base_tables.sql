-- ============================================================
-- Part 2: 创建枚举类型和基础表
-- ============================================================

-- 用户角色枚举
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('sales_rep', 'sales_manager', 'admin', 'csm');
    END IF;
END $$;

-- 团队表
CREATE TABLE IF NOT EXISTS public.teams (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    manager_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 用户资料表 (关联Supabase Auth users)
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

-- 添加team_id外键 (在profiles创建后)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints 
        WHERE constraint_name = 'fk_teams_manager'
    ) THEN
        ALTER TABLE public.teams 
            ADD CONSTRAINT fk_teams_manager 
            FOREIGN KEY (manager_id) REFERENCES public.profiles(id);
    END IF;
END $$;

-- 客户表
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

-- 商机表
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

SELECT 'Part 2 completed' as status;
