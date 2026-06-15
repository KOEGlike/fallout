import { Skeleton } from '@/components/admin/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/admin/ui/table'

interface DataTableSkeletonProps {
  columns: number
  rows?: number
  headers?: string[]
}

// Placeholder shown via Inertia <Deferred> while a list page's data prop loads.
// Matches DataTable's bordered shell so the swap-in is shift-free.
export function DataTableSkeleton({ columns, rows = 10, headers }: DataTableSkeletonProps) {
  const colCount = headers?.length ?? columns
  return (
    <div>
      <div className="overflow-hidden rounded-md border border-border">
        <Table>
          <TableHeader>
            <TableRow>
              {Array.from({ length: colCount }).map((_, i) => (
                <TableHead key={i}>{headers ? headers[i] : <Skeleton className="h-4 w-16" />}</TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {Array.from({ length: rows }).map((_, r) => (
              <TableRow key={r}>
                {Array.from({ length: colCount }).map((_, c) => (
                  <TableCell key={c}>
                    <Skeleton className="h-4" style={{ width: `${55 + ((r * 7 + c * 13) % 40)}%` }} />
                  </TableCell>
                ))}
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </div>
      <div className="flex items-center justify-between pt-4">
        <Skeleton className="h-4 w-32" />
      </div>
    </div>
  )
}
