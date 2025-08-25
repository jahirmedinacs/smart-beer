document.addEventListener('DOMContentLoaded', () => {
    const API_BASE_URL = 'http://localhost:8000/api/historical/';
    const tableBody = document.querySelector('#historical-table tbody');
    const paginationControls = document.getElementById('pagination-controls');
    
    let currentPageUrl = API_BASE_URL;

    const fetchHistoricalData = async (url) => {
        try {
            const response = await fetch(url);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            const data = await response.json();
            
            renderTable(data.results);
            renderPagination(data);

        } catch (error) {
            tableBody.innerHTML = `<tr><td colspan="5">Error loading data: ${error.message}</td></tr>`;
            console.error('Error fetching historical data:', error);
        }
    };

    const renderTable = (data) => {
        tableBody.innerHTML = ''; // Clear table
        
        if (!data || data.length === 0) {
            tableBody.innerHTML = '<tr><td colspan="5">No historical data found.</td></tr>';
            return;
        }

        data.forEach(row => {
            const tr = document.createElement('tr');
            // MongoDB returns an object for the date, we access $date
            const timestamp = row.timestamp?.$date ? new Date(row.timestamp.$date).toLocaleString() : 'N/A';
            tr.innerHTML = `
                <td>${timestamp}</td>
                <td>${row.batch_id}</td>
                <td>${row.temperature_celsius}</td>
                <td>${row.pressure_psi}</td>
                <td>${row.co2_vol}</td>
            `;
            tableBody.appendChild(tr);
        });
    };

    const renderPagination = (data) => {
        paginationControls.innerHTML = '';
        
        const prevButton = document.createElement('button');
        prevButton.textContent = 'Previous';
        prevButton.disabled = !data.previous;
        prevButton.addEventListener('click', () => fetchHistoricalData(data.previous));

        const nextButton = document.createElement('button');
        nextButton.textContent = 'Next';
        nextButton.disabled = !data.next;
        nextButton.addEventListener('click', () => fetchHistoricalData(data.next));
        
        const countSpan = document.createElement('span');
        countSpan.textContent = ` Total: ${data.count} records `;

        paginationControls.appendChild(prevButton);
        paginationControls.appendChild(countSpan);
        paginationControls.appendChild(nextButton);
    };

    // Load initial data
    fetchHistoricalData(currentPageUrl);
});
