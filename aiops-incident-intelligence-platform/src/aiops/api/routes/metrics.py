from fastapi import APIRouter, Depends

from aiops.api.deps import get_pipeline
from aiops.api.schemas import IncidentOut, MetricIngestRequest, incident_out_from_domain
from aiops.pipeline import AiopsPipeline, MetricPoint

router = APIRouter(prefix="/metrics", tags=["metrics"])


@router.post("", response_model=list[IncidentOut])
def ingest_metric(
    payload: MetricIngestRequest, pipeline: AiopsPipeline = Depends(get_pipeline)
) -> list[IncidentOut]:
    point = MetricPoint(
        entity=payload.entity,
        metric=payload.metric,
        value=payload.value,
        timestamp=payload.timestamp,
    )
    incidents = pipeline.ingest_metric(point)
    return [incident_out_from_domain(incident) for incident in incidents]
