from fastapi import APIRouter, Depends

from aiops.api.deps import get_pipeline
from aiops.api.schemas import TopologyRequest
from aiops.pipeline import AiopsPipeline

router = APIRouter(prefix="/topology", tags=["topology"])


@router.post("", status_code=204)
def update_topology(
    payload: TopologyRequest, pipeline: AiopsPipeline = Depends(get_pipeline)
) -> None:
    """Register service-dependency edges used by the correlation engine
    to decide whether two anomalous entities belong to the same incident,
    and to rank the probable root cause.
    """
    for edge in payload.edges:
        pipeline.correlation.graph.add_edge(edge.upstream, edge.downstream)
