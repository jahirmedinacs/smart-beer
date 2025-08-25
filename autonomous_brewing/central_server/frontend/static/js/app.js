document.addEventListener('DOMContentLoaded', () => {
    const API_URL = 'http://localhost:8000/api/realtime/';
    const tableBody = document.querySelector('#realtime-table tbody');

    const fetchRealtimeData = async () => {
        try {
            const response = await fetch(API_URL);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json();
            
            renderTable(data);

        } catch (error) {
            tableBody.innerHTML = `<tr><td colspan="5">Error loading data: ${error.message}</td></tr>`;
            console.error('Error fetching realtime data:', error);
        }
    };

    const renderTable = (data) => {
        tableBody.innerHTML = ''; // Clear table
        
        if (!data || data.length === 0) {
            tableBody.innerHTML = '<tr><td colspan="5">No recent data in cache.</td></tr>';
            return;
        }

        data.forEach(row => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${new Date(row.timestamp).toLocaleString()}</td>
                <td>${row.batch_id}</td>
                <td>${row.temperature_celsius}</td>
                <td>${row.pressure_psi}</td>
                <td>${row.co2_vol}</td>
            `;
            tableBody.appendChild(tr);
        });
    };

    // Load data on start and then every 5 seconds
    fetchRealtimeData();
    setInterval(fetchRealtimeData, 5000);
});
