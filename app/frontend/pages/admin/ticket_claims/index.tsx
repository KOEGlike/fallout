import { useState } from 'react'
import type { ReactNode } from 'react'
import { router, Link, usePage } from '@inertiajs/react'
import AdminLayout from '@/layouts/AdminLayout'
import { Badge } from '@/components/admin/ui/badge'
import { Button } from '@/components/admin/ui/button'
import { Card, CardContent } from '@/components/admin/ui/card'
import { Checkbox } from '@/components/admin/ui/checkbox'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/admin/ui/alert-dialog'
import { CheckIcon, ClockIcon, ExternalLinkIcon, XIcon } from 'lucide-react'

type Project = {
  id: number
  name: string
}

type ClaimUser = {
  id: number
  display_name: string
  email: string
  avatar: string
  approved_hours: number
  total_hours: number
  projects: Project[]
}

type Claim = {
  id: number
  state: 'pending' | 'approved' | 'rejected'
  created_at: string
  user: ClaimUser
}

const STATE_VARIANTS: Record<string, 'default' | 'secondary' | 'destructive' | 'outline'> = {
  pending: 'outline',
  approved: 'default',
  rejected: 'destructive',
}

const HOURS_GOAL = 60

function ClaimCard({
  claim,
  selected,
  onSelect,
}: {
  claim: Claim
  selected: boolean
  onSelect: (id: number, checked: boolean) => void
}) {
  const [processing, setProcessing] = useState(false)
  const pct = Math.min((claim.user.approved_hours / HOURS_GOAL) * 100, 100)

  function approve() {
    setProcessing(true)
    router.patch(`/admin/ticket_claims/${claim.id}/approve`, {}, { onFinish: () => setProcessing(false) })
  }

  function reject() {
    setProcessing(true)
    router.patch(`/admin/ticket_claims/${claim.id}/reject`, {}, { onFinish: () => setProcessing(false) })
  }

  return (
    <Card className={selected ? 'ring-2 ring-primary' : ''}>
      <CardContent className="px-4 py-3">
        {/* Row 1: identity + actions */}
        <div className="flex items-center gap-3">
          {claim.state === 'pending' && (
            <Checkbox
              checked={selected}
              onCheckedChange={(checked) => onSelect(claim.id, !!checked)}
              className="shrink-0"
              aria-label={`Select ${claim.user.display_name}`}
            />
          )}
          <img src={claim.user.avatar} alt={claim.user.display_name} className="size-8 rounded-full shrink-0" />
          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5 flex-wrap">
              <span className="font-semibold text-sm">{claim.user.display_name}</span>
              <Badge variant={STATE_VARIANTS[claim.state] ?? 'outline'} className="text-[10px] px-1.5 py-0">
                {claim.state}
              </Badge>
              <span className="text-xs text-muted-foreground">
                · {claim.user.email} · {claim.created_at}
              </span>
            </div>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            <Button variant="outline" size="sm" asChild>
              <Link href={`/admin/users/${claim.user.id}`}>
                <ExternalLinkIcon className="size-3.5" />
                View
              </Link>
            </Button>
            {claim.state === 'pending' && (
              <>
                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <Button variant="outline" size="sm" disabled={processing}>
                      <XIcon className="size-3.5" />
                      Reject
                    </Button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Reject claim for {claim.user.display_name}?</AlertDialogTitle>
                      <AlertDialogDescription>
                        This will mark their claim as rejected. They will not receive a ticket.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction variant="destructive" onClick={reject} disabled={processing}>
                        Reject
                      </AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>

                <AlertDialog>
                  <AlertDialogTrigger asChild>
                    <Button size="sm" disabled={processing}>
                      <CheckIcon className="size-3.5" />
                      Approve
                    </Button>
                  </AlertDialogTrigger>
                  <AlertDialogContent>
                    <AlertDialogHeader>
                      <AlertDialogTitle>Approve ticket for {claim.user.display_name}?</AlertDialogTitle>
                      <AlertDialogDescription>
                        This will mark the claim as approved and register <strong>{claim.user.display_name}</strong> (
                        {claim.user.email}) with the Attend API. They'll receive an invitation email.
                      </AlertDialogDescription>
                    </AlertDialogHeader>
                    <AlertDialogFooter>
                      <AlertDialogCancel>Cancel</AlertDialogCancel>
                      <AlertDialogAction onClick={approve} disabled={processing}>
                        Approve & send invite
                      </AlertDialogAction>
                    </AlertDialogFooter>
                  </AlertDialogContent>
                </AlertDialog>
              </>
            )}
          </div>
        </div>

        {/* Row 2: hours bar + projects */}
        <div className="flex items-center gap-3 mt-2 pl-[calc(1rem+0.75rem+2rem)]">
          <div className="flex items-center gap-2 w-40 shrink-0">
            <div className="h-1.5 rounded-full bg-muted overflow-hidden flex-1">
              <div
                className="h-full bg-primary rounded-full transition-all duration-300"
                style={{ width: `${pct}%` }}
              />
            </div>
            <span className="text-xs text-muted-foreground whitespace-nowrap">
              {claim.user.approved_hours}h / {HOURS_GOAL}h
            </span>
          </div>
          {claim.user.projects.length > 0 && (
            <div className="flex flex-wrap gap-1">
              {claim.user.projects.map((p) => (
                <Link
                  key={p.id}
                  href={`/admin/projects/${p.id}`}
                  className="inline-flex items-center rounded border border-border px-1.5 py-px text-[11px] hover:bg-muted transition-colors"
                >
                  {p.name}
                </Link>
              ))}
            </div>
          )}
        </div>
      </CardContent>
    </Card>
  )
}

const STATES = ['', 'pending', 'approved', 'rejected']

export default function AdminTicketClaimsIndex({ claims, state_filter }: { claims: Claim[]; state_filter: string }) {
  const { errors } = usePage<{ errors?: { base?: string[] } }>().props
  const [selectedIds, setSelectedIds] = useState<Set<number>>(new Set())
  const [bulkProcessing, setBulkProcessing] = useState(false)

  const pendingClaims = claims.filter((c) => c.state === 'pending')
  const pendingCount = pendingClaims.length
  const allPendingSelected = pendingCount > 0 && pendingClaims.every((c) => selectedIds.has(c.id))
  const somePendingSelected = pendingClaims.some((c) => selectedIds.has(c.id))

  function filterByState(state: string) {
    setSelectedIds(new Set())
    router.get('/admin/ticket_claims', state ? { state } : {}, { preserveState: true })
  }

  function handleSelect(id: number, checked: boolean) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      checked ? next.add(id) : next.delete(id)
      return next
    })
  }

  function handleSelectAll(checked: boolean) {
    if (checked) {
      setSelectedIds(new Set(pendingClaims.map((c) => c.id)))
    } else {
      setSelectedIds(new Set())
    }
  }

  function bulkApprove() {
    setBulkProcessing(true)
    router.patch(
      '/admin/ticket_claims/bulk_approve',
      { claim_ids: Array.from(selectedIds) },
      {
        onFinish: () => {
          setBulkProcessing(false)
          setSelectedIds(new Set())
        },
      },
    )
  }

  function bulkReject() {
    setBulkProcessing(true)
    router.patch(
      '/admin/ticket_claims/bulk_reject',
      { claim_ids: Array.from(selectedIds) },
      {
        onFinish: () => {
          setBulkProcessing(false)
          setSelectedIds(new Set())
        },
      },
    )
  }

  const selectedCount = selectedIds.size

  return (
    <div className="pb-20">
      <div className="flex items-center justify-between mb-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Ticket Claims</h1>
          {pendingCount > 0 && (
            <p className="text-sm text-muted-foreground mt-0.5">
              {pendingCount} pending {pendingCount === 1 ? 'claim' : 'claims'} awaiting review
            </p>
          )}
        </div>
      </div>

      {errors?.base && (
        <div className="mb-4 rounded-md border border-destructive bg-destructive/10 p-3 text-sm text-destructive">
          {Array.isArray(errors.base) ? errors.base[0] : errors.base}
        </div>
      )}

      <div className="flex items-center justify-between mb-6">
        <div className="flex flex-wrap gap-1.5">
          {STATES.map((s) => (
            <Button
              key={s}
              variant={state_filter === s ? 'default' : 'outline'}
              size="sm"
              onClick={() => filterByState(s)}
            >
              {s === '' ? 'All' : s}
              {s === 'pending' && pendingCount > 0 && (
                <span className="ml-1.5 inline-flex items-center justify-center size-4 rounded-full bg-background/20 text-[10px] font-bold">
                  {pendingCount}
                </span>
              )}
            </Button>
          ))}
        </div>

        {pendingCount > 0 && (
          <div className="flex items-center gap-2 text-sm text-muted-foreground">
            <Checkbox
              id="select-all"
              checked={allPendingSelected}
              data-state={somePendingSelected && !allPendingSelected ? 'indeterminate' : undefined}
              onCheckedChange={handleSelectAll}
            />
            <label htmlFor="select-all" className="cursor-pointer select-none">
              {allPendingSelected ? 'Deselect all' : 'Select all pending'}
            </label>
          </div>
        )}
      </div>

      {claims.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-16 text-muted-foreground">
          <ClockIcon className="size-8 mb-3 opacity-40" />
          <p className="text-sm">No claims {state_filter ? `with state "${state_filter}"` : 'yet'}</p>
        </div>
      ) : (
        <div className="space-y-3">
          {claims.map((claim) => (
            <ClaimCard key={claim.id} claim={claim} selected={selectedIds.has(claim.id)} onSelect={handleSelect} />
          ))}
        </div>
      )}

      {selectedCount > 0 && (
        <div className="fixed bottom-6 left-1/2 -translate-x-1/2 z-50">
          <div className="flex items-center gap-3 rounded-xl border bg-card px-4 py-3 shadow-lg">
            <span className="text-sm font-medium">
              {selectedCount} {selectedCount === 1 ? 'claim' : 'claims'} selected
            </span>
            <div className="h-4 w-px bg-border" />

            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button variant="outline" size="sm" disabled={bulkProcessing}>
                  <XIcon className="size-3.5" />
                  Reject all
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>
                    Reject {selectedCount} {selectedCount === 1 ? 'claim' : 'claims'}?
                  </AlertDialogTitle>
                  <AlertDialogDescription>
                    This will mark {selectedCount === 1 ? 'this claim' : `all ${selectedCount} selected claims`} as
                    rejected. The {selectedCount === 1 ? 'user' : 'users'} will not receive a ticket.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Cancel</AlertDialogCancel>
                  <AlertDialogAction variant="destructive" onClick={bulkReject} disabled={bulkProcessing}>
                    Reject {selectedCount === 1 ? 'claim' : `${selectedCount} claims`}
                  </AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>

            <AlertDialog>
              <AlertDialogTrigger asChild>
                <Button size="sm" disabled={bulkProcessing}>
                  <CheckIcon className="size-3.5" />
                  Approve all
                </Button>
              </AlertDialogTrigger>
              <AlertDialogContent>
                <AlertDialogHeader>
                  <AlertDialogTitle>
                    Approve {selectedCount} {selectedCount === 1 ? 'claim' : 'claims'}?
                  </AlertDialogTitle>
                  <AlertDialogDescription>
                    This will approve {selectedCount === 1 ? 'this claim' : `all ${selectedCount} selected claims`} and
                    send {selectedCount === 1 ? 'an invitation email' : `${selectedCount} invitation emails`} via the
                    Attend API.
                  </AlertDialogDescription>
                </AlertDialogHeader>
                <AlertDialogFooter>
                  <AlertDialogCancel>Cancel</AlertDialogCancel>
                  <AlertDialogAction onClick={bulkApprove} disabled={bulkProcessing}>
                    Approve & send {selectedCount === 1 ? 'invite' : `${selectedCount} invites`}
                  </AlertDialogAction>
                </AlertDialogFooter>
              </AlertDialogContent>
            </AlertDialog>

            <Button variant="ghost" size="sm" onClick={() => setSelectedIds(new Set())} disabled={bulkProcessing}>
              Clear
            </Button>
          </div>
        </div>
      )}
    </div>
  )
}

AdminTicketClaimsIndex.layout = (page: ReactNode) => <AdminLayout>{page}</AdminLayout>
