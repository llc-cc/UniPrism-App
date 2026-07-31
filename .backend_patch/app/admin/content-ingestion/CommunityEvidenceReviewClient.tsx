'use client';

import Link from 'next/link';
import { useCallback, useState } from 'react';

type ReviewStatus = 'pending' | 'approved' | 'rejected' | 'all';
type PlatformFilter = 'all' | 'zhihu' | 'tieba';
type DimensionFilter =
  | 'all'
  | 'school'
  | 'major'
  | 'course'
  | 'employment'
  | 'dormitory'
  | 'cafeteria'
  | 'student_club';

type ReviewItem = {
  contentItemId: string;
  institutionName: string;
  majorName: string | null;
  platform: string;
  dimension: string;
  sanitizedText: string;
  qualityScore: number;
  credibilityScore: number | null;
  analysisStatus: string;
  claims: unknown;
  sourceUrl: string;
  collectedAt: string;
  reviewStatus: string;
  updatedAt: string;
};

type ReviewPage = {
  page: number;
  pageSize: number;
  total: number;
  items: ReviewItem[];
};

const DIMENSION_LABELS: Record<Exclude<DimensionFilter, 'all'>, string> = {
  school: '学校整体',
  major: '专业',
  course: '课程',
  employment: '就业',
  dormitory: '宿舍',
  cafeteria: '食堂',
  student_club: '社团',
};

function claimText(claims: unknown) {
  if (!Array.isArray(claims)) return 'AI 尚未完成结构化判断';
  return claims
    .map((claim) => (
      claim && typeof claim === 'object' && 'text' in claim
        ? String(claim.text)
        : ''
    ))
    .filter(Boolean)
    .join('；') || 'AI 尚未完成结构化判断';
}

export function CommunityEvidenceReviewClient({
  initialPage,
}: {
  initialPage: ReviewPage;
}) {
  const [data, setData] = useState(initialPage);
  const [status, setStatus] = useState<ReviewStatus>('pending');
  const [platform, setPlatform] = useState<PlatformFilter>('all');
  const [dimension, setDimension] = useState<DimensionFilter>('all');
  const [query, setQuery] = useState('');
  const [loading, setLoading] = useState(false);
  const [mutatingId, setMutatingId] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  const load = useCallback(async (
    page: number,
    nextStatus = status,
    nextPlatform = platform,
    nextDimension = dimension,
  ) => {
    setLoading(true);
    setMessage(null);
    try {
      const params = new URLSearchParams({
        status: nextStatus,
        page: String(page),
      });
      if (nextPlatform !== 'all') params.set('platform', nextPlatform);
      if (nextDimension !== 'all') params.set('dimension', nextDimension);
      if (query.trim()) params.set('query', query.trim());
      const response = await fetch(
        `/api/admin/content-ingestion/community-evidence?${params}&pageSize=20`,
        { cache: 'no-store' },
      );
      const body = await response.json() as {
        ok?: boolean;
        data?: ReviewPage;
        error?: { message?: string };
      };
      if (!response.ok || !body.ok || !body.data) {
        throw new Error(body.error?.message ?? '加载失败');
      }
      setData(body.data);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : '加载失败');
    } finally {
      setLoading(false);
    }
  }, [dimension, platform, query, status]);

  const review = useCallback(async (
    item: ReviewItem,
    action: 'approve' | 'reject' | 'edit_and_approve',
  ) => {
    let editedText: string | undefined;
    if (action === 'edit_and_approve') {
      editedText = window.prompt('请修改脱敏后的正文：', item.sanitizedText) ?? undefined;
      if (!editedText || editedText === item.sanitizedText) return;
    }
    setMutatingId(item.contentItemId);
    setMessage(null);
    try {
      const response = await fetch(
        `/api/admin/content-ingestion/community-evidence/${encodeURIComponent(item.contentItemId)}`,
        {
          method: 'PATCH',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action,
            expectedUpdatedAt: item.updatedAt,
            ...(editedText ? { editedText } : {}),
          }),
        },
      );
      const body = await response.json() as {
        ok?: boolean;
        error?: { message?: string };
      };
      if (!response.ok || !body.ok) {
        throw new Error(body.error?.message ?? '审核失败');
      }
      setMessage('审核结果已保存。');
      await load(data.page);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : '审核失败');
    } finally {
      setMutatingId(null);
    }
  }, [data.page, load]);

  const totalPages = Math.max(1, Math.ceil(data.total / data.pageSize));
  return (
    <div className="grid gap-5">
      <section className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <div className="flex flex-col gap-3 lg:flex-row lg:items-end">
          <label className="grid gap-1 text-xs font-bold text-slate-500">
            审核状态
            <select value={status} onChange={(event) => {
              const value = event.target.value as ReviewStatus;
              setStatus(value);
              void load(1, value, platform, dimension);
            }} className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-800">
              <option value="pending">待审核</option>
              <option value="approved">已通过</option>
              <option value="rejected">已拒绝</option>
              <option value="all">全部</option>
            </select>
          </label>
          <label className="grid gap-1 text-xs font-bold text-slate-500">
            平台
            <select value={platform} onChange={(event) => {
              const value = event.target.value as PlatformFilter;
              setPlatform(value);
              void load(1, status, value, dimension);
            }} className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-800">
              <option value="all">全部平台</option>
              <option value="zhihu">知乎</option>
              <option value="tieba">贴吧</option>
            </select>
          </label>
          <label className="grid gap-1 text-xs font-bold text-slate-500">
            内容维度
            <select value={dimension} onChange={(event) => {
              const value = event.target.value as DimensionFilter;
              setDimension(value);
              void load(1, status, platform, value);
            }} className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-800">
              <option value="all">全部维度</option>
              {Object.entries(DIMENSION_LABELS).map(([value, label]) => (
                <option key={value} value={value}>{label}</option>
              ))}
            </select>
          </label>
          <label className="grid min-w-64 flex-1 gap-1 text-xs font-bold text-slate-500">
            关键词
            <input value={query} onChange={(event) => setQuery(event.target.value)} className="rounded-xl border border-slate-200 px-3 py-2 text-sm text-slate-800" placeholder="搜索脱敏正文" />
          </label>
          <button type="button" disabled={loading} onClick={() => void load(1)} className="rounded-xl bg-violet-600 px-4 py-2 text-sm font-black text-white disabled:opacity-60">
            {loading ? '加载中…' : '筛选'}
          </button>
        </div>
        {message ? <p className="mt-3 rounded-xl bg-slate-50 px-3 py-2 text-sm text-slate-700">{message}</p> : null}
      </section>

      {data.items.length === 0 ? (
        <section className="rounded-2xl border border-dashed border-slate-300 bg-white p-12 text-center text-sm text-slate-500">
          当前筛选条件下没有内容。
        </section>
      ) : data.items.map((item) => (
        <article key={item.contentItemId} className="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
          <div className="flex flex-wrap items-center gap-2 text-xs font-bold">
            <span className="rounded-full bg-violet-50 px-3 py-1 text-violet-700">{item.institutionName}</span>
            <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{item.platform}</span>
            <span className="rounded-full bg-slate-100 px-3 py-1 text-slate-600">{DIMENSION_LABELS[item.dimension as keyof typeof DIMENSION_LABELS] ?? item.dimension}</span>
            <span className="text-slate-400">质量 {item.qualityScore} · 可信度 {item.credibilityScore ?? '待分析'}</span>
          </div>
          <p className="mt-4 whitespace-pre-wrap text-sm leading-7 text-slate-800">{item.sanitizedText}</p>
          <div className="mt-4 rounded-xl bg-slate-50 p-3 text-sm leading-6 text-slate-600">
            <b className="text-slate-900">AI 辅助观点：</b>{claimText(item.claims)}
          </div>
          <div className="mt-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
            <div className="text-xs text-slate-400">
              采集于 {new Date(item.collectedAt).toLocaleString('zh-CN')} ·{' '}
              <a href={item.sourceUrl} target="_blank" rel="noreferrer" className="font-bold text-violet-700 hover:underline">查看公开来源</a>
            </div>
            {item.reviewStatus === 'human_required' ? (
              <div className="flex flex-wrap gap-2">
                <button type="button" disabled={mutatingId === item.contentItemId} onClick={() => void review(item, 'edit_and_approve')} className="rounded-xl border border-violet-200 px-3 py-2 text-sm font-black text-violet-700 disabled:opacity-50">编辑后通过</button>
                <button type="button" disabled={mutatingId === item.contentItemId} onClick={() => void review(item, 'reject')} className="rounded-xl border border-red-200 px-3 py-2 text-sm font-black text-red-700 disabled:opacity-50">拒绝</button>
                <button type="button" disabled={mutatingId === item.contentItemId} onClick={() => void review(item, 'approve')} className="rounded-xl bg-emerald-600 px-3 py-2 text-sm font-black text-white disabled:opacity-50">通过</button>
              </div>
            ) : null}
          </div>
        </article>
      ))}

      <section className="flex items-center justify-between rounded-2xl border border-slate-200 bg-white px-5 py-4 text-sm text-slate-500">
        <span>共 {data.total} 条 · 第 {data.page}/{totalPages} 页</span>
        <div className="flex gap-2">
          <button type="button" disabled={data.page <= 1 || loading} onClick={() => void load(data.page - 1)} className="rounded-xl border border-slate-200 px-3 py-2 font-bold disabled:opacity-40">上一页</button>
          <button type="button" disabled={data.page >= totalPages || loading} onClick={() => void load(data.page + 1)} className="rounded-xl border border-slate-200 px-3 py-2 font-bold disabled:opacity-40">下一页</button>
        </div>
      </section>
    </div>
  );
}

export type { ReviewPage };
