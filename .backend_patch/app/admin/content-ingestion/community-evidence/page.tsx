import type { Metadata } from 'next';
import Link from 'next/link';
import { redirect } from 'next/navigation';
import { auth } from '@/lib/auth';
import { ROUTES } from '@/lib/routes';
import { isAdminRole } from '@/lib/security/admin';
import { prisma } from '@/lib/db';
import { listCommunityEvidence } from '@/lib/adminCommunityEvidence';
import {
  CommunityEvidenceReviewClient,
} from '../CommunityEvidenceReviewClient';

export const metadata: Metadata = {
  title: '社区内容审核 | UniPrism Admin',
};
export const dynamic = 'force-dynamic';

/** 审核页属于内容监控中心，不扩展或修改其他管理模块。 */
export default async function CommunityEvidenceReviewPage() {
  const session = await auth();
  if (!session?.user) redirect(ROUTES.login);
  if (!isAdminRole(session.user.role)) {
    return (
      <main className="min-h-screen bg-slate-50 px-6 py-12 text-slate-900">
        <div className="mx-auto max-w-2xl rounded-2xl border border-slate-200 bg-white p-8 shadow-sm">
          <h1 className="text-2xl font-black">没有管理员权限</h1>
          <Link href={ROUTES.login} className="mt-6 inline-flex rounded-xl bg-[#007a66] px-5 py-3 text-sm font-black text-white">返回登录</Link>
        </div>
      </main>
    );
  }

  const initialPage = await listCommunityEvidence({
    status: 'pending',
    page: 1,
    pageSize: 20,
  }, prisma);
  return (
    <main className="min-h-screen bg-slate-50 px-6 py-8 text-slate-900">
      <div className="mx-auto grid max-w-6xl gap-6">
        <header className="rounded-2xl border border-slate-200 bg-white p-6 shadow-sm">
          <Link href="/admin/content-ingestion" className="text-sm font-black text-violet-700">← 返回内容采集监控中心</Link>
          <h1 className="mt-4 text-3xl font-black text-slate-950">社区内容审核</h1>
          <p className="mt-2 text-sm leading-7 text-slate-600">
            审核北京大学知乎、贴吧公开内容。只有管理员明确通过的证据才可进入后续聚合流程。
          </p>
        </header>
        <CommunityEvidenceReviewClient initialPage={initialPage} />
      </div>
    </main>
  );
}
