'use client';

import Link from 'next/link';
import { useCallback, useEffect, useMemo, useState } from 'react';
import { ChevronLeft, ChevronRight, Clock3, Power, RefreshCw, Search } from 'lucide-react';
import type {
  AdminContentIngestionDashboard,
  AdminContentIngestionSource,
  AdminContentSourceDomain,
} from '@/lib/adminContentIngestion';
import type { ContentIngestionAutomationState } from '@/lib/content-ingestion/automationControl';
import {
  fetchUniversityCrawlerAutomation,
  updateUniversityCrawlerAutomation,
} from '@/lib/content-ingestion/automationAdminClient';

const REFRESH_INTERVAL_MS = 30_000;
const PAGE_SIZE = 20;
const DOMAIN_ORDER: AdminContentSourceDomain[] = ['education', 'public_authority', 'social_trends', 'user_context', 'research_career', 'other'];
const DOMAIN_LABELS: Record<AdminContentSourceDomain, string> = {
  education: '高校与教育', public_authority: '政府与权威目录', social_trends: '社会热点',
  user_context: '用户相关内容', research_career: '科研与职业数据', other: '其他来源',
};

type DomainFilter = 'all' | AdminContentSourceDomain;
type StatusFilter = 'all' | 'enabled' | 'paused' | 'abnormal';

function formatNumber(value: number) {
  return value.toLocaleString('zh-CN');
}

function formatDateTime(value: string | null) {
  if (!value) return '暂无';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '未知' : new Intl.DateTimeFormat('zh-CN', {
    month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(date);
}

const STATUS_LABEL: Record<string, string> = {
  enabled: '正常', paused: '已暂停', blocked: '已阻止', error: '异常',
};

function statusClass(status: string) {
  if (status === 'enabled') return 'bg-emerald-50 text-emerald-700';
  if (status === 'paused') return 'bg-amber-50 text-amber-700';
  return 'bg-red-50 text-red-700';
}

function sourcePriority(source: AdminContentIngestionSource) {
  if (source.status === 'error' || source.status === 'blocked') return 0;
  if (source.status === 'paused') return 1;
  return 2;
}

function StatCard({ label, value, hint, accent = 'text-slate-950' }: { label: string; value: number; hint: string; accent?: string }) {
  return (
    <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
      <div className="text-sm font-bold text-slate-500">{label}</div>
      <div className={`mt-2 text-3xl font-black ${accent}`}>{formatNumber(value)}</div>
      <div className="mt-2 text-xs leading-5 text-slate-500">{hint}</div>
    </section>
  );
}

function SourceDirectoryRow({ source }: { source: AdminContentIngestionSource }) {
  const latestBatch = source.recentBatches[0] ?? null;
  return (
    <article className="grid gap-4 border-t border-slate-100 px-5 py-4 first:border-t-0 lg:grid-cols-[minmax(260px,1.5fr)_minmax(240px,1.2fr)_150px_180px_44px] lg:items-center">
      <div className="min-w-0">
        <div className="flex flex-wrap items-center gap-2">
          <h3 className="truncate text-base font-black text-slate-950">{source.displayName}</h3>
          <span className={`rounded-full px-2.5 py-1 text-xs font-black ${statusClass(source.status)}`}>{STATUS_LABEL[source.status] ?? '未知'}</span>
        </div>
        <p className="mt-1 text-xs text-slate-500">{source.domainLabel} · {source.scheduleDescription}</p>
      </div>

      <div className="flex flex-wrap gap-1.5">
        {source.contentScopes.length > 0 ? source.contentScopes.slice(0, 4).map((scope) => (
          <span key={scope.code} className="rounded-lg bg-violet-50 px-2 py-1 text-xs font-bold text-violet-700">{scope.label} {formatNumber(scope.count)}</span>
        )) : <span className="text-xs text-slate-400">尚未识别内容类型</span>}
        {source.contentScopes.length > 4 ? <span className="rounded-lg bg-slate-100 px-2 py-1 text-xs font-bold text-slate-500">+{source.contentScopes.length - 4}</span> : null}
      </div>

      <div className="text-sm text-slate-600">
        <div>入库 <b className="text-slate-950">{formatNumber(source.contentItemCount)}</b></div>
        <div className="mt-1 text-xs text-slate-400">任务 {formatNumber(source.batchCount)} 次</div>
      </div>

      <div className="text-sm text-slate-600">
        <div>最近成功：{formatDateTime(source.lastSuccessAt)}</div>
        <div className="mt-1 text-xs text-slate-400">最近任务：抓取 {latestBatch?.fetchedCount ?? 0} · 新增 {latestBatch?.createdCount ?? 0} · 失败 {latestBatch?.failedCount ?? 0}</div>
        {latestBatch?.agentMetrics ? (
          <div className="mt-1 text-xs text-violet-600">
            Agent 任务：完成 {latestBatch.agentMetrics.completedTasks} · 阻断 {latestBatch.agentMetrics.blockedTasks} · 失败 {latestBatch.agentMetrics.failedTasks}
          </div>
        ) : null}
      </div>

      <Link href={`/admin/content-ingestion/${encodeURIComponent(source.code)}`} aria-label={`查看${source.displayName}详情`} className="inline-flex h-10 w-10 items-center justify-center rounded-xl text-violet-700 hover:bg-violet-50">
        <ChevronRight className="h-5 w-5" />
      </Link>
    </article>
  );
}

/**
 * 管理端监控目录：页面可修改高校自动采集开关，但敏感密钥和服务器控制权限仍只留在后端。
 */
export function AdminContentIngestionDashboardClient({
  initialDashboard,
  initialAutomation,
}: {
  initialDashboard: AdminContentIngestionDashboard;
  initialAutomation: ContentIngestionAutomationState;
}) {
  const [dashboard, setDashboard] = useState(initialDashboard);
  const [automation, setAutomation] = useState(initialAutomation);
  const [isRefreshing, setIsRefreshing] = useState(false);
  const [isUpdatingAutomation, setIsUpdatingAutomation] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [automationError, setAutomationError] = useState<string | null>(null);
  const [query, setQuery] = useState('');
  const [domain, setDomain] = useState<DomainFilter>('all');
  const [status, setStatus] = useState<StatusFilter>('all');
  const [page, setPage] = useState(1);

  const refresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      const dashboardRequest = fetch('/api/admin/content-ingestion', { cache: 'no-store' });
      const automationRequest = fetchUniversityCrawlerAutomation();
      const response = await dashboardRequest;
      const body = await response.json().catch(() => null) as { ok?: boolean; data?: AdminContentIngestionDashboard; error?: { message?: string } } | null;
      if (!response.ok || !body?.ok || !body.data) throw new Error(body?.error?.message ?? '刷新失败');
      const latestAutomation = await automationRequest;
      setDashboard(body.data);
      setAutomation(latestAutomation);
      setError(null);
      setAutomationError(null);
    } catch (refreshError) {
      setError(refreshError instanceof Error ? refreshError.message : '刷新失败');
    } finally {
      setIsRefreshing(false);
    }
  }, []);

  useEffect(() => {
    const id = window.setInterval(() => void refresh(), REFRESH_INTERVAL_MS);
    return () => window.clearInterval(id);
  }, [refresh]);

  useEffect(() => setPage(1), [query, domain, status]);

  const toggleAutomation = useCallback(async () => {
    setIsUpdatingAutomation(true);
    setAutomationError(null);
    try {
      // 服务端成功落库后才切换视觉状态，避免网络失败时产生“已开启/关闭”的错觉。
      const latestAutomation = await updateUniversityCrawlerAutomation(!automation.enabled);
      setAutomation(latestAutomation);
    } catch (updateError) {
      setAutomationError(updateError instanceof Error ? updateError.message : '高校自动采集设置更新失败');
    } finally {
      setIsUpdatingAutomation(false);
    }
  }, [automation.enabled]);

  const domainCounts = useMemo(() => dashboard.sources.reduce<Record<AdminContentSourceDomain, number>>((counts, source) => {
    counts[source.domain] += 1;
    return counts;
  }, { education: 0, public_authority: 0, social_trends: 0, user_context: 0, research_career: 0, other: 0 }), [dashboard.sources]);

  const filteredSources = useMemo(() => {
    const normalizedQuery = query.trim().toLocaleLowerCase('zh-CN');
    return dashboard.sources
      .filter((source) => domain === 'all' || source.domain === domain)
      .filter((source) => status === 'all'
        || (status === 'abnormal' ? source.status === 'error' || source.status === 'blocked' : source.status === status))
      .filter((source) => !normalizedQuery || [
        source.displayName, source.code, source.domainLabel, ...source.contentScopes.map((scope) => scope.label),
      ].some((value) => value.toLocaleLowerCase('zh-CN').includes(normalizedQuery)))
      .sort((left, right) => sourcePriority(left) - sourcePriority(right) || left.displayName.localeCompare(right.displayName, 'zh-CN'));
  }, [dashboard.sources, domain, query, status]);

  const totalPages = Math.max(1, Math.ceil(filteredSources.length / PAGE_SIZE));
  const currentPage = Math.min(page, totalPages);
  const pageSources = filteredSources.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);
  const groupedSources = DOMAIN_ORDER.map((key) => ({
    key,
    label: DOMAIN_LABELS[key],
    sources: pageSources.filter((source) => source.domain === key),
  })).filter((group) => group.sources.length > 0);

  return (
    <div className="grid gap-6">
      <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-2 text-sm text-slate-500"><Clock3 className="h-4 w-4" />每 30 秒自动刷新 · 最近更新 {formatDateTime(dashboard.updatedAt)}</div>
        <div className="flex flex-wrap gap-2">
          <Link href="/admin/content-ingestion/community-evidence" className="inline-flex items-center justify-center rounded-xl bg-violet-600 px-4 py-2 text-sm font-black text-white hover:bg-violet-700">
            内容审核
          </Link>
          <button type="button" onClick={() => void refresh()} disabled={isRefreshing} className="inline-flex items-center justify-center gap-2 rounded-xl border border-slate-200 bg-white px-4 py-2 text-sm font-black text-slate-700 hover:bg-slate-50 disabled:opacity-60"><RefreshCw className={isRefreshing ? 'h-4 w-4 animate-spin' : 'h-4 w-4'} />立即刷新</button>
        </div>
      </div>
      {error ? <div className="rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-bold text-red-700">{error}</div> : null}

      <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="flex flex-col gap-5 lg:flex-row lg:items-center lg:justify-between">
          <div>
            <div className="flex flex-wrap items-center gap-3">
              <h2 className="text-xl font-black text-slate-950">高校自动采集</h2>
              <span className={`rounded-full px-3 py-1 text-xs font-black ${automation.enabled ? 'bg-emerald-50 text-emerald-700' : 'bg-slate-100 text-slate-600'}`}>
                {automation.enabled ? '已开启' : '已关闭'}
              </span>
            </div>
            <p className="mt-2 text-sm leading-6 text-slate-500">
              {automation.enabled
                ? `系统将在${automation.scheduleLabel}自动采集高校公开内容，下次计划 ${formatDateTime(automation.nextRunAt)}。`
                : '定时任务会跳过高校采集，不会抓取或写入新内容；管理员手动测试仍可使用。'}
            </p>
            <p className="mt-1 text-xs text-slate-400">
              北京时间 · 设置更新于 {formatDateTime(automation.updatedAt)}
            </p>
          </div>
          <button
            type="button"
            aria-pressed={automation.enabled}
            onClick={() => void toggleAutomation()}
            disabled={isUpdatingAutomation}
            className={`inline-flex min-w-40 items-center justify-center gap-2 rounded-xl px-5 py-3 text-sm font-black text-white disabled:cursor-not-allowed disabled:opacity-60 ${automation.enabled ? 'bg-slate-700 hover:bg-slate-800' : 'bg-emerald-600 hover:bg-emerald-700'}`}
          >
            <Power className="h-4 w-4" />
            {isUpdatingAutomation ? '正在保存…' : automation.enabled ? '关闭定时采集' : '开启定时采集'}
          </button>
        </div>
        {automationError ? <div className="mt-4 rounded-xl border border-red-200 bg-red-50 px-4 py-3 text-sm font-bold text-red-700">{automationError}</div> : null}
      </section>

      <section className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
        <StatCard label="数据源" value={dashboard.summary.sources} hint={`${dashboard.summary.enabledSources} 个正常 · ${dashboard.summary.pausedSources} 个暂停`} />
        <StatCard label="异常数据源" value={dashboard.summary.abnormalSources} hint="被阻止或执行异常的来源" accent="text-red-600" />
        <StatCard label="运行中任务" value={dashboard.summary.runningBatches} hint="等待或运行中的采集批次" accent="text-blue-700" />
        <StatCard label="今日抓取" value={dashboard.summary.todayFetchedCount} hint="按北京时间当天统计" />
        <StatCard label="今日新增/更新" value={dashboard.summary.todayWrittenCount} hint="清洗后实际写入的内容" accent="text-emerald-700" />
        <StatCard label="今日失败" value={dashboard.summary.todayFailedCount} hint="进入详情可查看失败原因" accent="text-red-600" />
      </section>

      <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="flex flex-col gap-4 lg:flex-row lg:items-center lg:justify-between">
          <div><h2 className="text-xl font-black text-slate-950">数据源目录</h2><p className="mt-1 text-sm text-slate-500">按来源领域和内容类型归类，点击数据源查看任务与错误详情。</p></div>
          <div className="flex flex-col gap-2 sm:flex-row">
            <label className="relative min-w-[260px]"><Search className="pointer-events-none absolute left-3 top-2.5 h-4 w-4 text-slate-400" /><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="搜索学校、平台或内容类型" className="w-full rounded-xl border border-slate-200 py-2 pl-9 pr-3 text-sm outline-none focus:border-violet-400" /></label>
            <select value={status} onChange={(event) => setStatus(event.target.value as StatusFilter)} className="rounded-xl border border-slate-200 bg-white px-3 py-2 text-sm font-bold text-slate-700 outline-none focus:border-violet-400"><option value="all">全部状态</option><option value="enabled">正常</option><option value="paused">已暂停</option><option value="abnormal">异常</option></select>
          </div>
        </div>

        <div className="mt-5 flex gap-2 overflow-x-auto pb-2">
          <button type="button" onClick={() => setDomain('all')} className={`whitespace-nowrap rounded-xl px-3 py-2 text-sm font-black ${domain === 'all' ? 'bg-violet-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>全部 {dashboard.sources.length}</button>
          {DOMAIN_ORDER.map((key) => <button key={key} type="button" onClick={() => setDomain(key)} className={`whitespace-nowrap rounded-xl px-3 py-2 text-sm font-black ${domain === key ? 'bg-violet-600 text-white' : 'bg-slate-100 text-slate-600 hover:bg-slate-200'}`}>{DOMAIN_LABELS[key]} {domainCounts[key]}</button>)}
        </div>
      </section>

      {groupedSources.length > 0 ? <div className="grid gap-5">{groupedSources.map((group) => (
        <section key={group.key} className="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm">
          <header className="flex items-center justify-between bg-slate-50 px-5 py-4"><h2 className="font-black text-slate-950">{group.label}</h2><span className="text-xs font-bold text-slate-500">本页 {group.sources.length} 个来源</span></header>
          <div>{group.sources.map((source) => <SourceDirectoryRow key={source.id} source={source} />)}</div>
        </section>
      ))}</div> : <div className="rounded-2xl border border-dashed border-slate-300 bg-white px-6 py-12 text-center text-sm text-slate-500">没有符合当前筛选条件的数据源。</div>}

      <div className="flex flex-col gap-3 rounded-2xl border border-slate-200 bg-white px-5 py-4 text-sm sm:flex-row sm:items-center sm:justify-between">
        <div className="text-slate-500">共 {formatNumber(filteredSources.length)} 个来源 · 第 {currentPage}/{totalPages} 页 · 每页最多 {PAGE_SIZE} 个</div>
        <div className="flex gap-2"><button type="button" onClick={() => setPage((value) => Math.max(1, value - 1))} disabled={currentPage <= 1} className="inline-flex items-center gap-1 rounded-xl border border-slate-200 px-3 py-2 font-black text-slate-700 disabled:opacity-40"><ChevronLeft className="h-4 w-4" />上一页</button><button type="button" onClick={() => setPage((value) => Math.min(totalPages, value + 1))} disabled={currentPage >= totalPages} className="inline-flex items-center gap-1 rounded-xl border border-slate-200 px-3 py-2 font-black text-slate-700 disabled:opacity-40">下一页<ChevronRight className="h-4 w-4" /></button></div>
      </div>
    </div>
  );
}
