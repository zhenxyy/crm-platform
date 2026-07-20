
// ============================================================
// Supabase Edge Functions - CRM多Agent协同平台
// 部署: supabase functions deploy agent-orchestrator
// ============================================================

// -------------------- Function 1: Agent Orchestrator --------------------
// 文件: supabase/functions/agent-orchestrator/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders });
    }

    try {
        const { opportunity_id, trigger_agent } = await req.json();

        // 创建Supabase admin客户端 (绕过RLS)
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
        );

        // 获取商机数据
        const { data: opportunity } = await supabaseAdmin
            .from('opportunities')
            .select('*, customers(*)')
            .eq('id', opportunity_id)
            .single();

        if (!opportunity) throw new Error('Opportunity not found');

        // Agent执行链
        const agentChain = [
            'lead_scoring',
            'customer_profiling', 
            'knowledge_retrieval',
            'task_planning',
            'tool_execution',
            'quality_assurance',
            'approval_guard',
            'crm_writeback'
        ];

        const results = [];

        for (const agentName of agentChain) {
            const startTime = Date.now();

            // 模拟Agent执行 (实际应调用LLM API)
            const agentResult = await executeAgent(agentName, opportunity, supabaseAdmin);

            const latency = Date.now() - startTime;

            // 记录Agent运行
            await supabaseAdmin.from('agent_runs').insert({
                opportunity_id,
                agent_name: agentName,
                status: agentResult.success ? 'success' : 'failed',
                latency_ms: latency,
                token_count: agentResult.tokens || 0,
                cost_usd: agentResult.cost || 0,
                output_data: agentResult.output,
                confidence: agentResult.confidence,
                error_message: agentResult.error
            });

            results.push({ agent: agentName, ...agentResult });

            // 如果Agent失败且是关键节点，中断链
            if (!agentResult.success && agentName === 'quality_assurance') {
                await supabaseAdmin.from('opportunities')
                    .update({ current_stage: 'HOLD', requires_human: true })
                    .eq('id', opportunity_id);
                break;
            }
        }

        return new Response(
            JSON.stringify({ success: true, results }),
            { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );

    } catch (error) {
        return new Response(
            JSON.stringify({ error: error.message }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        );
    }
});

// 模拟Agent执行逻辑
async function executeAgent(agentName, opportunity, supabase) {
    // 实际项目中这里调用OpenAI/Claude API
    const mockResults = {
        lead_scoring: {
            success: true,
            tokens: 150,
            cost: 0.08,
            confidence: 0.87,
            output: {
                score: 82,
                grade: 'A',
                dimensions: { industry: 15, source: 12, budget: 20, timeline: 12 }
            }
        },
        customer_profiling: {
            success: true,
            tokens: 320,
            cost: 0.15,
            confidence: 0.82,
            output: {
                key_contacts: [
                    { role: 'CTO', focus: 'API能力', influence: '决策者' }
                ],
                risk_signals: ['预算充足', '决策窗口紧迫']
            }
        },
        // ... 其他Agent
    };

    return mockResults[agentName] || { success: true, tokens: 100, cost: 0.05, confidence: 0.9, output: {} };
}

// -------------------- Function 2: Embedding Generator --------------------
// 文件: supabase/functions/generate-embedding/index.ts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

serve(async (req) => {
    const { text } = await req.json();

    // 调用OpenAI Embedding API
    const response = await fetch('https://api.openai.com/v1/embeddings', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            model: 'text-embedding-3-large',
            input: text,
            dimensions: 1024
        })
    });

    const { data } = await response.json();

    return new Response(
        JSON.stringify({ embedding: data[0].embedding }),
        { headers: { 'Content-Type': 'application/json' } }
    );
});

// -------------------- Function 3: LLM Agent Router --------------------
// 文件: supabase/functions/llm-agent/index.ts

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

serve(async (req) => {
    const { agent_type, context, model = 'gpt-4o' } = await req.json();

    // 构建系统提示
    const systemPrompts = {
        lead_scoring: `你是一个CRM线索评级专家。根据客户信息，输出JSON格式的评分结果：
            {"score": 0-100, "grade": "S/A/B/C/D", "reasoning": "...", "dimensions": {...}}`,

        customer_profiling: `你是一个客户画像分析专家。根据CRM数据，输出JSON格式的画像：
            {"key_contacts": [...], "pain_points": [...], "buying_signals": [...]}`,

        knowledge_retrieval: `你是一个企业知识库检索专家。根据查询，输出最相关的文档和推荐话术。`,

        task_planning: `你是一个销售任务规划专家。根据商机阶段，输出跟进任务DAG。`
    };

    const response = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${Deno.env.get('OPENAI_API_KEY')}`,
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            model,
            messages: [
                { role: 'system', content: systemPrompts[agent_type] || '你是一个AI助手。' },
                { role: 'user', content: JSON.stringify(context) }
            ],
            temperature: 0.3,
            response_format: { type: 'json_object' }
        })
    });

    const result = await response.json();

    return new Response(
        JSON.stringify({
            output: JSON.parse(result.choices[0].message.content),
            tokens: result.usage.total_tokens,
            cost: (result.usage.prompt_tokens * 0.005 + result.usage.completion_tokens * 0.015) / 1000
        }),
        { headers: { 'Content-Type': 'application/json' } }
    );
});

// -------------------- Function 4: Cost Controller --------------------
// 文件: supabase/functions/cost-controller/index.ts

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

serve(async (req) => {
    const { user_id, estimated_cost } = await req.json();

    const supabase = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    // 获取用户预算
    const { data: profile } = await supabase
        .from('profiles')
        .select('monthly_token_budget, token_used_this_month')
        .eq('id', user_id)
        .single();

    if (!profile) throw new Error('Profile not found');

    const remaining = profile.monthly_token_budget - profile.token_used_this_month;

    // 成本预算控制逻辑
    let model = 'gpt-4o';
    let action = 'proceed';

    if (remaining < estimated_cost) {
        if (remaining < 0.5) {
            action = 'block';
            model = 'none';
        } else if (remaining < 2) {
            action = 'degrade';
            model = 'claude-3.5-haiku';
        } else {
            action = 'degrade';
            model = 'claude-3.5-sonnet';
        }
    }

    // 更新使用量
    await supabase.from('profiles')
        .update({ token_used_this_month: profile.token_used_this_month + estimated_cost })
        .eq('id', user_id);

    return new Response(
        JSON.stringify({ action, model, remaining_budget: remaining }),
        { headers: { 'Content-Type': 'application/json' } }
    );
});
