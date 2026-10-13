import DataBrokerFinder from '@/components/DataBrokerFinder';
export default function FindBrokers(_props: { onTabChange: (tab: string) => void }) {
  return <><p className="mb-4 text-muted-foreground">Results are suggestions from a local directory, not evidence that a broker holds your data.</p><DataBrokerFinder /></>;
}
