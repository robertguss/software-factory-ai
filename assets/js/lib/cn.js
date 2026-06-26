import { clsx } from "clsx"
import { twMerge } from "tailwind-merge"

// Merge conditional class lists, with later Tailwind utilities winning over
// earlier conflicting ones. The shadcn convention every primitive builds on.
export function cn(...inputs) {
  return twMerge(clsx(inputs))
}
