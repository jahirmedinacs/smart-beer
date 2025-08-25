from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.pagination import PageNumberPagination
import redis
import json
import pymongo
from bson import json_util
from datetime import datetime, timedelta, timezone

# --- Database Connections ---
REDIS_CLIENT = redis.Redis(host='localhost', port=6379, db=0, decode_responses=True)
MONGO_CLIENT = pymongo.MongoClient("mongodb://root:example@localhost:27017/")
MONGO_DB = MONGO_CLIENT['brewing_db']
MONGO_COLLECTION = MONGO_DB['sensor_readings']

class RealtimeDataView(APIView):
    """
    Endpoint to get the most recent data from the Redis cache.
    """
    def get(self, request, *args, **kwargs):
        try:
            keys = REDIS_CLIENT.keys('sensor_data:*')
            if not keys:
                return Response([])
            
            # Get all values and sort them in Python
            pipeline = REDIS_CLIENT.pipeline()
            for key in keys:
                pipeline.get(key)
            
            values = pipeline.execute()
            
            # Deserialize and sort by timestamp descending
            data = sorted(
                [json.loads(v) for v in values if v], 
                key=lambda x: x['timestamp'], 
                reverse=True
            )
            
            return Response(data[:20]) # Return the 20 most recent
        except Exception as e:
            return Response({"error": str(e)}, status=500)


class StandardResultsSetPagination(PageNumberPagination):
    page_size = 50
    page_size_query_param = 'page_size'
    max_page_size = 1000

class HistoricalDataView(APIView):
    """
    Endpoint to get paginated historical data from MongoDB.
    """
    pagination_class = StandardResultsSetPagination

    @property
    def paginator(self):
        if not hasattr(self, '_paginator'):
            self._paginator = self.pagination_class()
        return self._paginator

    def get(self, request, *args, **kwargs):
        try:
            # Build query based on parameters (e.g., batch_id, dates)
            query = {}
            batch_id = request.query_params.get('batch_id')
            if batch_id:
                query['batch_id'] = batch_id

            # Get documents sorted by timestamp
            queryset = MONGO_COLLECTION.find(query).sort("timestamp", pymongo.DESCENDING)
            
            # Paginate the results
            page = self.paginator.paginate_queryset(list(queryset), request, view=self)
            
            # Safely serialize BSON to JSON
            serialized_page = json.loads(json_util.dumps(page))

            return self.paginator.get_paginated_response(serialized_page)
        except Exception as e:
            return Response({"error": str(e)}, status=500)
