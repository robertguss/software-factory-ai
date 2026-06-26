import { memo } from "react"
import { Handle, Position } from "@xyflow/react"
import SliceCard from "@/components/slice-card"

// The React Flow custom node for a slice: a SliceCard between connection
// handles. Defined at module scope and memoized so the node-type registry stays
// stable across renders (React Flow re-mounts nodes if the type identity churns).
function SliceNode({ data }) {
  return (
    <>
      <Handle type="target" position={Position.Left} className="!bg-border" />
      <SliceCard node={data} />
      <Handle type="source" position={Position.Right} className="!bg-border" />
    </>
  )
}

export default memo(SliceNode)
