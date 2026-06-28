import { memo, useEffect, useRef, useState } from "react"
import { Handle, Position } from "@xyflow/react"
import { motion, useReducedMotion } from "motion/react"
import { Pin } from "lucide-react"
import SliceCard from "@/components/slice-card"
import { cn } from "@/lib/cn"
import { TRANSITION, VARIANTS, variantFor } from "@/lib/motion-grammar"

// The React Flow custom node for a slice: a SliceCard between connection
// handles. Defined at module scope and memoized so the node-type registry stays
// stable across renders (React Flow re-mounts nodes if the type identity churns).
//
// Motion grammar (R2): the card animates only when its state actually changes —
// the signature variant for the prev→next transition plays once, then settles.
// prefers-reduced-motion disables all motion (the selector returns `idle`).
function SliceNode({ data }) {
  const reducedMotion = useReducedMotion()
  const prevState = useRef(data.state)
  const [variant, setVariant] = useState("idle")

  useEffect(() => {
    if (data.state === prevState.current) return
    setVariant(variantFor(prevState.current, data.state, { reducedMotion }))
    prevState.current = data.state
  }, [data.state, reducedMotion])

  // A pin (R4) keeps this node from being auto-folded away. The affordance shows
  // on hover, and stays visible while pinned. Only rendered when the canvas wires
  // an `onTogglePin` into the node data, so non-canvas uses stay unaffected.
  const { onTogglePin, pinned } = data

  return (
    <div className="group relative">
      <Handle type="target" position={Position.Left} className="!bg-border" />
      <motion.div animate={variant} variants={VARIANTS} transition={TRANSITION}>
        <SliceCard node={data} scale="nano" />
      </motion.div>
      {onTogglePin && (
        <button
          type="button"
          aria-label={pinned ? "Unpin node" : "Pin node"}
          aria-pressed={!!pinned}
          onClick={(e) => {
            e.stopPropagation()
            onTogglePin(data.id)
          }}
          className={cn(
            "absolute -right-1.5 -top-1.5 rounded bg-surface p-0.5 text-muted transition-opacity",
            pinned ? "text-fg opacity-100" : "opacity-0 hover:text-fg group-hover:opacity-100",
          )}
        >
          <Pin size={11} aria-hidden="true" fill={pinned ? "currentColor" : "none"} />
        </button>
      )}
      <Handle type="source" position={Position.Right} className="!bg-border" />
    </div>
  )
}

export default memo(SliceNode)
