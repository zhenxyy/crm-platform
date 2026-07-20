
// ============================================================
// CRM多Agent协同平台 - Supabase 前端集成代码
// 文件: supabase-client.js
// ============================================================

// 通过CDN引入 (适合纯HTML项目)
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>

// 初始化Supabase客户端
const SUPABASE_URL = 'https://ebsndpzlfjeuojjkwycn.supabase.co';
const SUPABASE_ANON_KEY = 'your-anon-key-here'; // 从Supabase Dashboard获取

const supabase = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: true
    },
    realtime: {
        params: {
            eventsPerSecond: 10
        }
    }
});

// ============================================================
// 1. 认证相关
// ============================================================

const AuthAPI = {
    // 邮箱登录
    async signIn(email, password) {
        const { data, error } = await supabase.auth.signInWithPassword({
            email,
            password
        });
        if (error) throw error;
        return data;
    },

    // 获取当前用户
    async getCurrentUser() {
        const { data: { user }, error } = await supabase.auth.getUser();
        if (error) throw error;
        return user;
    },

    // 获取用户资料 (含角色、团队)
    async getProfile() {
        const { data: { user } } = await supabase.auth.getUser();
        if (!user) return null;

        const { data, error } = await supabase
            .from('profiles')
            .select(`
                *,
                teams:team_id (name, manager_id)
            `)
            .eq('id', user.id)
            .single();

        if (error) throw error;
        return data;
    },

    // 登出
    async signOut() {
        const { error } = await supabase.auth.signOut();
        if (error) throw error;
    }
};

// ============================================================
// 2. 商机管理 (Opportunities)
// ============================================================

const OpportunityAPI = {
    // 创建新商机 (提交资料后调用)
    async create(customerData, requirements) {
        // 1. 创建客户
        const { data: customer, error: customerError } = await supabase
            .from('customers')
            .insert([{
                name: customerData.customerName,
                company_name: customerData.companyName,
                industry: customerData.industry,
                contact_info: {
                    phone: customerData.contact,
                    source: customerData.source
                },
                source: customerData.source,
                assigned_to: (await AuthAPI.getCurrentUser())?.id
            }])
            .select()
            .single();

        if (customerError) throw customerError;

        // 2. 创建商机
        const { data: opportunity, error: oppError } = await supabase
            .from('opportunities')
            .insert([{
                customer_id: customer.id,
                title: `${customerData.companyName} - ${customerData.industry || '通用'}商机`,
                budget_range: customerData.budget,
                expected_close_date: this._calcCloseDate(customerData.timeline),
                owner_id: (await AuthAPI.getCurrentUser())?.id,
                current_stage: 'NEW'
            }])
            .select()
            .single();

        if (oppError) throw oppError;

        return { customer, opportunity };
    },

    // 更新商机评级结果
    async updateRating(opportunityId, ratingData) {
        const { data, error } = await supabase
            .from('opportunities')
            .update({
                lead_score: ratingData.score,
                lead_grade: ratingData.grade,
                scenario_type: ratingData.scenario,
                ai_confidence: ratingData.confidence,
                requires_human: ratingData.requiresHuman,
                current_stage: ratingData.requiresHuman ? 'HOLD' : 'SCORED'
            })
            .eq('id', opportunityId)
            .select()
            .single();

        if (error) throw error;
        return data;
    },

    // 获取商机列表 (带筛选)
    async list(filters = {}) {
        let query = supabase
            .from('opportunities')
            .select(`
                *,
                customers:customer_id (name, company_name, industry),
                profiles:owner_id (full_name, role)
            `);

        if (filters.grade) query = query.eq('lead_grade', filters.grade);
        if (filters.stage) query = query.eq('current_stage', filters.stage);
        if (filters.team) query = query.eq('team_id', filters.team);
        if (filters.search) {
            query = query.or(`title.ilike.%${filters.search}%,customers.company_name.ilike.%${filters.search}%`);
        }

        const { data, error } = await query.order('created_at', { ascending: false });
        if (error) throw error;
        return data;
    },

    // 获取商机详情
    async getById(id) {
        const { data, error } = await supabase
            .from('opportunities')
            .select(`
                *,
                customers:customer_id (*),
                agent_runs:opportunities!inner (*),
                customer_profiles:opportunities!inner (*),
                task_plans:opportunities!inner (*)
            `)
            .eq('id', id)
            .single();

        if (error) throw error;
        return data;
    },

    // 计算预期成交日期
    _calcCloseDate(timeline) {
        const now = new Date();
        const map = {
            '1个月内': 30,
            '1-3个月': 60,
            '3-6个月': 120,
            '6个月以上': 180
        };
        const days = map[timeline] || 90;
        now.setDate(now.getDate() + days);
        return now.toISOString().split('T')[0];
    }
};

// ============================================================
// 3. Agent运行记录
// ============================================================

const AgentRunAPI = {
    // 记录Agent运行
    async logRun(opportunityId, agentName, runData) {
        const { data, error } = await supabase
            .from('agent_runs')
            .insert([{
                opportunity_id: opportunityId,
                agent_name: agentName,
                status: runData.status,
                latency_ms: runData.latency,
                token_count: runData.tokens,
                cost_usd: runData.cost,
                output_data: runData.output,
                confidence: runData.confidence,
                error_message: runData.error
            }])
            .select()
            .single();

        if (error) throw error;
        return data;
    },

    // 获取Agent运行历史
    async getRunsByOpportunity(opportunityId) {
        const { data, error } = await supabase
            .from('agent_runs')
            .select('*')
            .eq('opportunity_id', opportunityId)
            .order('created_at', { ascending: true });

        if (error) throw error;
        return data;
    },

    // 获取Agent效能统计 (用于管理驾驶舱)
    async getAgentStats(teamId, days = 30) {
        const { data, error } = await supabase.rpc('get_agent_stats', {
            p_team_id: teamId,
            p_days: days
        });

        if (error) throw error;
        return data;
    }
};

// ============================================================
// 4. RAG知识检索
// ============================================================

const KnowledgeAPI = {
    // 向量相似度搜索 (调用RPC函数)
    async vectorSearch(queryEmbedding, options = {}) {
        const { data, error } = await supabase.rpc('match_knowledge_docs', {
            query_embedding: queryEmbedding,
            match_threshold: options.threshold || 0.7,
            match_count: options.count || 5,
            p_industry_tags: options.industryTags || []
        });

        if (error) throw error;
        return data;
    },

    // 全文关键词搜索
    async textSearch(keywords, options = {}) {
        let query = supabase
            .from('knowledge_docs')
            .select('*')
            .textSearch('title', keywords, { type: 'websearch' });

        if (options.docType) query = query.eq('doc_type', options.docType);
        if (options.limit) query = query.limit(options.limit);

        const { data, error } = await query;
        if (error) throw error;
        return data;
    },

    // 混合检索 (向量 + 全文)
    async hybridSearch(query, embedding, options = {}) {
        const [vectorResults, textResults] = await Promise.all([
            this.vectorSearch(embedding, options),
            this.textSearch(query, options)
        ]);

        // RRF融合去重
        return this._rrfFusion(vectorResults, textResults);
    },

    // Reciprocal Rank Fusion
    _rrfFusion(vecResults, textResults, k = 60) {
        const scores = new Map();

        vecResults.forEach((doc, i) => {
            const id = doc.id;
            scores.set(id, {
                ...doc,
                rrf_score: (scores.get(id)?.rrf_score || 0) + 1 / (k + i + 1)
            });
        });

        textResults.forEach((doc, i) => {
            const id = doc.id;
            const existing = scores.get(id);
            scores.set(id, {
                ...doc,
                rrf_score: (existing?.rrf_score || 0) + 1 / (k + i + 1)
            });
        });

        return Array.from(scores.values())
            .sort((a, b) => b.rrf_score - a.rrf_score)
            .slice(0, 10);
    }
};

// ============================================================
// 5. 实时订阅 (Realtime)
// ============================================================

const RealtimeAPI = {
    // 订阅商机状态变化
    subscribeOpportunities(callback) {
        return supabase
            .channel('opportunities_changes')
            .on(
                'postgres_changes',
                { event: '*', schema: 'public', table: 'opportunities' },
                (payload) => callback(payload)
            )
            .subscribe();
    },

    // 订阅Agent运行状态
    subscribeAgentRuns(opportunityId, callback) {
        return supabase
            .channel(`agent_runs_${opportunityId}`)
            .on(
                'postgres_changes',
                { 
                    event: 'INSERT', 
                    schema: 'public', 
                    table: 'agent_runs',
                    filter: `opportunity_id=eq.${opportunityId}`
                },
                (payload) => callback(payload.new)
            )
            .subscribe();
    },

    // 订阅审批状态
    subscribeApprovals(callback) {
        return supabase
            .channel('approvals_changes')
            .on(
                'postgres_changes',
                { event: '*', schema: 'public', table: 'approvals' },
                (payload) => callback(payload)
            )
            .subscribe();
    },

    // 取消订阅
    unsubscribe(channel) {
        supabase.removeChannel(channel);
    }
};

// ============================================================
// 6. 管理驾驶舱数据
// ============================================================

const DashboardAPI = {
    // 获取团队概览
    async getTeamOverview(teamId) {
        const { data, error } = await supabase
            .from('opportunities')
            .select('current_stage, lead_grade, estimated_value')
            .eq('team_id', teamId);

        if (error) throw error;

        // 前端聚合计算
        const stats = {
            total: data.length,
            byStage: {},
            byGrade: {},
            totalValue: 0,
            conversionRate: 0
        };

        data.forEach(opp => {
            stats.byStage[opp.current_stage] = (stats.byStage[opp.current_stage] || 0) + 1;
            stats.byGrade[opp.lead_grade] = (stats.byGrade[opp.lead_grade] || 0) + 1;
            stats.totalValue += opp.estimated_value || 0;
        });

        const won = stats.byStage['WON'] || 0;
        const totalClosed = won + (stats.byStage['LOST'] || 0);
        stats.conversionRate = totalClosed > 0 ? (won / totalClosed * 100).toFixed(1) : 0;

        return stats;
    },

    // 获取销售漏斗数据
    async getFunnelData(teamId) {
        const stages = ['NEW', 'SCORED', 'PROFILING', 'PLANNED', 'EXECUTING', 'QA_PASSED', 'APPROVED', 'WON'];
        const { data, error } = await supabase
            .from('opportunities')
            .select('current_stage')
            .eq('team_id', teamId);

        if (error) throw error;

        const counts = {};
        data.forEach(opp => {
            counts[opp.current_stage] = (counts[opp.current_stage] || 0) + 1;
        });

        return stages.map(stage => ({
            stage,
            count: counts[stage] || 0,
            label: this._stageLabel(stage)
        }));
    },

    // 获取Agent效能分析
    async getAgentPerformance(teamId, days = 30) {
        const { data, error } = await supabase
            .from('agent_runs')
            .select('agent_name, status, latency_ms, cost_usd, token_count')
            .gte('created_at', new Date(Date.now() - days * 86400000).toISOString())
            .in('opportunity_id', supabase
                .from('opportunities')
                .select('id')
                .eq('team_id', teamId)
            );

        if (error) throw error;

        // 按Agent聚合
        const stats = {};
        data.forEach(run => {
            if (!stats[run.agent_name]) {
                stats[run.agent_name] = { count: 0, totalLatency: 0, totalCost: 0, totalTokens: 0, success: 0 };
            }
            const s = stats[run.agent_name];
            s.count++;
            s.totalLatency += run.latency_ms || 0;
            s.totalCost += run.cost_usd || 0;
            s.totalTokens += run.token_count || 0;
            if (run.status === 'success') s.success++;
        });

        return Object.entries(stats).map(([name, s]) => ({
            agent: name,
            calls: s.count,
            avgLatency: Math.round(s.totalLatency / s.count),
            avgCost: (s.totalCost / s.count).toFixed(4),
            avgTokens: Math.round(s.totalTokens / s.count),
            successRate: (s.success / s.count * 100).toFixed(1)
        }));
    },

    _stageLabel(stage) {
        const labels = {
            'NEW': '新线索', 'SCORED': '已评级', 'PROFILING': '画像构建中',
            'PLANNED': '任务已规划', 'EXECUTING': '执行中', 'QA_PASSED': '质检通过',
            'APPROVED': '审批通过', 'WON': '赢单', 'LOST': '输单', 'HOLD': '人工接管'
        };
        return labels[stage] || stage;
    }
};

// ============================================================
// 7. 导出
// ============================================================

window.CRMSupabase = {
    client: supabase,
    auth: AuthAPI,
    opportunities: OpportunityAPI,
    agents: AgentRunAPI,
    knowledge: KnowledgeAPI,
    realtime: RealtimeAPI,
    dashboard: DashboardAPI
};
