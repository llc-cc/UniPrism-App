import type { Metadata } from 'next';
import Link from 'next/link';
import { ArrowLeft, CircleAlert, ExternalLink } from 'lucide-react';
import { notFound, redirect } from 'next/navigation';
import { auth } from '@/lib/auth';
import { getAdminContentIngestionSourceDetail } from '@/lib/adminContentIngestion';
import { ROUTES } from '@/lib/routes';
import { isAdminRole } from '@/lib/security/admin';

export const metadata: Metadata = {
  title: '数据源详情 | UniPrism Admin',
};

export const dynamic = 'force-dynamic';

function formatDateTime(value: string | null) {
  if (!value) return '暂无';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '未知' : new Intl.DateTimeFormat('zh-CN', {
    year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false,
  }).format(date);
}

function formatDuration(startedAt: string | null, completedAt: string | null) {
  if (!startedAt || !completedAt) return '—';
  const seconds = Math.max(0, Math.round((new Date(completedAt).getTime() - new Date(startedAt).getTime()) / 1_000));
  if (Number.isNaN(seconds)) return '—';
  if (seconds < 60) return `${seconds} 秒`;
  const minutes = Math.floor(seconds / 60);
  return minutes < 60 ? `${minutes} 分 ${seconds % 60} 秒` : `${Math.floor(minutes / 60)} 小时 ${minutes % 60} 分`;
}

function sourceKindLabel(sourceKind: string) {
  if (sourceKind === 'official-university-public-page') return '高校官网网页解析';
  if (sourceKind === 'open-metadata-api') return '公开数据接口';
  if (sourceKind === 'public-api-metadata') return '公开接口元数据采集';
  return '受控内容采集';
}

const BATCH_STATUS_LABEL: Record<string, string> = {
  pending: '等待中', running: '运行中', completed: '已完成', partial: '部分完成', failed: '失败', cancelled: '已取消',
};

const TRIGGER_LABEL: Record<string, string> = {
  scheduled: '定时任务', manual: '人工发起', backfill: '历史补采', webhook: '外部通知',
};

/**
 * 单一数据源的运行详情。仅管理员可见，且只展示采集统计与受控错误摘要，不输出正文或抓取凭据。
 */
export default async function AdminContentIngestionSourceDetailPage({
  params,
}: {
  params: Promise<{ sourceCode: string }>;
}) {
  const session = await auth();
  if (!session?.user) redirect(ROUTES.login);
  if (!isAdminRole(session.user.role)) redirect('/admin/content-ingestion');

  const { sourceCode } = await params;
  const source = await getAdminContentIngestionSourceDetail(sourceCode);
  if (!source) notFound();

  return (
    <main className="min-h-screen bg-slate-50 px-6 py-8 text-slate-900">
      <div className="mx-auto grid max-w-6xl gap-6">
        <Link href="/admin/content-ingestion" className="inline-flex w-fit items-center gap-2 text-sm font-black text-violet-700 hover:text-violet-900">
          <ArrowLeft className="h-4 w-4" /> 返回内容采集中心
        </Link>

        <header className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
            <div>
              <div className="inline-flex rounded-full bg-emerald-50 px-3 py-1 text-xs font-black text-emerald-700">数据源详情</div>
              <h1 className="mt-3 text-3xl font-black text-slate-950">{source.displayName}</h1>
              <p className="mt-2 text-sm leading-7 text-slate-600">任务名称：{source.displayName}内容采集。页面仅用于观察 App 内容链路，不提供用户端内容或任务控制入口。</p>
            </div>
            {source.sourceUrl ? (
              <a href={source.sourceUrl} target="_blank" rel="noreferrer" className="inline-flex items-center gap-2 rounded-xl border border-slate-200 px-4 py-2 text-sm font-black text-slate-700 hover:bg-slate-50">
                查看公开来源 <ExternalLink className="h-4 w-4" />
              </a>
            ) : null}
          </div>

          <dl className="mt-6 grid gap-4 rounded-xl bg-slate-50 p-4 text-sm md:grid-cols-2 xl:grid-cols-3">
            <div><dt className="text-slate-500">来源领域</dt><dd className="mt-1 font-black text-slate-900">{source.domainLabel}</dd></div>
            <div><dt className="text-slate-500">采集方式</dt><dd className="mt-1 font-black text-slate-900">{sourceKindLabel(source.sourceKind)}</dd></div>
            <div><dt className="text-slate-500">执行方式</dt><dd className="mt-1 font-black text-slate-900">{source.scheduleDescription}</dd></div>
            <div><dt className="text-slate-500">数据源状态</dt><dd className="mt-1 font-black text-slate-900">{source.status === 'enabled' ? '正常' : source.status}</dd></div>
            <div><dt className="text-slate-500">最近成功</dt><dd className="mt-1 font-black text-slate-900">{formatDateTime(source.lastSuccessAt)}</dd></div>
            <div><dt className="text-slate-500">下次执行</dt><dd className="mt-1 font-black text-slate-900">{formatDateTime(source.nextSyncAt)}</dd></div>
            <div><dt className="text-slate-500">AI 处理状态</dt><dd className="mt-1 font-black text-slate-900">{source.allowAiProcess ? '已启用' : '暂未启用（等待来源授权）'}</dd></div>
            <div><dt className="text-slate-500">推荐到 App</dt><dd className="mt-1 font-black text-slate-900">{source.allowRecommend ? '已启用' : '暂未启用（等待来源授权）'}</dd></div>
            <div><dt className="text-slate-500">已入库内容</dt><dd className="mt-1 font-black text-slate-900">{source.contentItemCount.toLocaleString('zh-CN')} 条</dd></div>
            <div><dt className="text-slate-500">历史任务</dt><dd className="mt-1 font-black text-slate-900">{source.batchCount.toLocaleString('zh-CN')} 次</dd></div>
          </dl>

          <div className="mt-5">
            <h2 className="text-sm font-black text-slate-900">已归类内容</h2>
            <div className="mt-3 flex flex-wrap gap-2">
              {source.contentScopes.length > 0 ? source.contentScopes.map((scope) => <span key={scope.code} className="rounded-lg bg-violet-50 px-3 py-2 text-xs font-bold text-violet-700">{scope.label} · {scope.count.toLocaleString('zh-CN')} 条</span>) : <span className="text-sm text-slate-500">尚未入库可归类内容。</span>}
            </div>
          </div>
        </header>

        <section className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-xl font-black text-slate-950">历史任务</h2>
          <p className="mt-2 text-sm leading-6 text-slate-600">显示最近 50 次任务。新增、更新、重复均已通过清洗与去重；失败任务可在下方查看原因。</p>
          <div className="mt-5 overflow-x-auto rounded-xl border border-slate-100">
            <table className="min-w-[1120px] w-full text-sm">
              <thead className="bg-slate-50 text-left text-xs font-black text-slate-500"><tr><th className="px-4 py-3">触发来源</th><th className="px-4 py-3">状态</th><th className="px-4 py-3">开始时间</th><th className="px-4 py-3">结束时间</th><th className="px-4 py-3">耗时</th><th className="px-4 py-3">Agent 执行</th><th className="px-4 py-3 text-right">抓取</th><th className="px-4 py-3 text-right">新增</th><th className="px-4 py-3 text-right">更新</th><th className="px-4 py-3 text-right">重复</th><th className="px-4 py-3 text-right">失败</th></tr></thead>
              <tbody>{source.recentBatches.map((batch) => <tr key={batch.id} className="border-t border-slate-100 text-slate-700"><td className="px-4 py-3 font-bold">{TRIGGER_LABEL[batch.trigger] ?? '未知触发'}</td><td className="px-4 py-3">{BATCH_STATUS_LABEL[batch.status] ?? batch.status}</td><td className="px-4 py-3 whitespace-nowrap text-xs text-slate-500">{formatDateTime(batch.startedAt ?? batch.createdAt)}</td><td className="px-4 py-3 whitespace-nowrap text-xs text-slate-500">{formatDateTime(batch.completedAt)}</td><td className="px-4 py-3 whitespace-nowrap text-xs font-bold">{formatDuration(batch.startedAt, batch.completedAt)}</td><td className="px-4 py-3 text-xs leading-5 text-violet-700">{batch.agentMetrics ? <>完成 {batch.agentMetrics.completedTasks} · 阻断 {batch.agentMetrics.blockedTasks}<br />访问页 {batch.agentMetrics.pagesVisited} · 去重 {batch.agentMetrics.duplicatesRemoved}</> : '—'}</td><td className="px-4 py-3 text-right">{batch.fetchedCount}</td><td className="px-4 py-3 text-right text-emerald-700">{batch.createdCount}</td><td className="px-4 py-3 text-right text-teal-700">{batch.updatedCount}</td><td className="px-4 py-3 text-right text-slate-500">{batch.unchangedCount}</td><td className="px-4 py-3 text-right text-red-600">{batch.failedCount}</td></tr>)}</tbody>
            </table>
          </div>
        </section>

        <section id="errors" className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <h2 className="text-xl font-black text-slate-950">错误日志</h2>
          <p className="mt-2 text-sm leading-6 text-slate-600">仅展示可处理的错误摘要；页面不会展示正文、登录信息或爬虫密钥。</p>
          {source.failures.length === 0 ? <p className="mt-5 rounded-xl bg-emerald-50 px-4 py-3 text-sm font-bold text-emerald-700">最近 50 次任务没有失败记录。</p> : <div className="mt-5 grid gap-3">{source.failures.map((failure) => <article key={failure.batchId} className="flex gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4"><CircleAlert className="mt-0.5 h-5 w-5 shrink-0 text-amber-700" /><div><div className="font-black text-amber-900">{failure.errorCode ?? '采集或清洗未完成'} · 失败 {failure.failedCount} 条</div><div className="mt-1 text-xs text-amber-700">{formatDateTime(failure.occurredAt)}</div><p className="mt-2 text-sm leading-6 text-amber-900">{failure.message}</p></div></article>)}</div>}
        </section>
      </div>
    </main>
  );
}
