import { useState } from 'react';
import { db } from '@/lib/database';
import { toast } from '@/components/ui/use-toast';
export default function NewRequest({ onTabChange }: { onTabChange: (tab: string) => void }) {
  const [saving, setSaving] = useState(false);
  return <form className="space-y-4" onSubmit={async event => {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    setSaving(true);
    try {
      await db.createRequest({ brokerName: String(data.get('brokerName')).trim(), userEmail: String(data.get('email')).trim(), status: 'pending' });
      toast({ title: 'Request saved', description: 'Open the broker website to submit it manually.' });
      onTabChange('requests');
    } catch (error) { toast({ title: 'Unable to save request', description: String(error), variant: 'destructive' }); }
    finally { setSaving(false); }
  }}>
    <p>Record and track a removal request. No message is sent automatically.</p>
    <label className="block">Broker name<input className="block border rounded p-2 w-full" name="brokerName" required maxLength={200} /></label>
    <label className="block">Your email<input className="block border rounded p-2 w-full" name="email" type="email" required /></label>
    <button className="rounded bg-primary text-primary-foreground px-4 py-2" disabled={saving}>{saving ? 'Saving…' : 'Save request'}</button>
  </form>;
}
