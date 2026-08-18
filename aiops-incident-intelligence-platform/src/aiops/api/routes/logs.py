from fastapi import APIRouter, Depends

from aiops.api.deps import get_pipeline
from aiops.api.schemas import IncidentOut, LogIngestRequest, incident_out_from_domain
from aiops.pipeline import AiopsPipeline, LogLine

router = APIRouter(prefix="/logs", tags=["logs"])


@router.post("", response_model=IncidentOut | None)
def ingest_log(
    payload: LogIngestRequest, pipeline: AiopsPipeline = Depends(get_pipeline)
) -> IncidentOut | None:
    line = LogLine(entity=payload.entity, message=payload.message, timestamp=payload.timestamp)
    incident = pipeline.ingest_log(line)
    return incident_out_from_domain(incident) if incident is not None else None
