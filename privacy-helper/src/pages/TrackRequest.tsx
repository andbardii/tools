import { useEffect, useState } from 'react';
import { db } from '@/lib/database';
import type { DataRequest } from '@/lib/types';
import RequestList from '@/components/RequestList';
export default function TrackRequest(_props: { onTabChange: (tab: string) => void }) {
  const [requests, setRequests] = useState<DataRequest[]>([]);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(true);
  useEffect(() => { let active = true;
    db.getRequests().then(data => { if (active) setRequests(data); }).catch(error => { if (active) setError(String(error)); }).finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, []);
  if (loading) return <p>Loading requests…</p>;
  if (error) return <p role="alert">{error}</p>;
  if (!requests.length) return <p>No requests recorded yet.</p>;
  return <RequestList requests={requests} onUpdateRequest={async (id, updates) => {
    try { const updated = await db.updateRequest(id, updates); if (updated) setRequests(items => items.map(item => item.id === id ? updated : item)); }
    catch (error) { setError(String(error)); }
  }} />;
}
