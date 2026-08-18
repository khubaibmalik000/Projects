from fastapi import APIRouter

from aiops import __version__
from aiops.api.schemas import HealthOut

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthOut)
def health() -> HealthOut:
    return HealthOut(status="ok", version=__version__)
