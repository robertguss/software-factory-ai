import { memo, useEffect, useRef, useState } from "react"
import { Handle, Position } from "@xyflow/react"
import { motion, useReducedMotion } from "motion/react"
import SliceCard from "@/components/slice-card"
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

  return (
    <>
      <Handle type="target" position={Position.Left} className="!bg-border" />
      <motion.div animate={variant} variants={VARIANTS} transition={TRANSITION}>
        <SliceCard node={data} scale="nano" />
      </motion.div>
      <Handle type="source" position={Position.Right} className="!bg-border" />
    </>
  )
}

export default memo(SliceNode)
