from django.urls import path
from .views import RealtimeDataView, HistoricalDataView

urlpatterns = [
    path('realtime/', RealtimeDataView.as_view(), name='realtime_data'),
    path('historical/', HistoricalDataView.as_view(), name='historical_data'),
]
