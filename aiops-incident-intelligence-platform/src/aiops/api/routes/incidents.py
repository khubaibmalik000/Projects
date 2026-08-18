from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from aiops.api.deps import get_db
from aiops.api.schemas import IncidentDetailOut, IncidentOut
from aiops.repository import get_incident, list_incidents

router = APIRouter(prefix="/incidents", tags=["incidents"])


@router.get("", response_model=list[IncidentOut])
def list_incidents_route(
    status: str | None = None, limit: int = 100, db: Session = Depends(get_db)
) -> list[IncidentOut]:
    records = list_incidents(db, status=status, limit=limit)
    return [IncidentOut.model_validate(record, from_attributes=True) for record in records]


@router.get("/{incident_id}", response_model=IncidentDetailOut)
def get_incident_route(incident_id: str, db: Session = Depends(get_db)) -> IncidentDetailOut:
    record = get_incident(db, incident_id)
    if record is None:
        raise HTTPException(status_code=404, detail=f"incident '{incident_id}' not found")
    return IncidentDetailOut.model_validate(record, from_attributes=True)
