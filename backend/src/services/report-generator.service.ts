import { Pool, PoolClient } from 'pg';
import PDFDocument = require('pdfkit');
import * as csv from 'csv-writer';
const anyCsv: any = csv;
import { EmergencyRequestRepository } from '../repositories/emergency-request.repository';

/**
 * Service class for generating reports
 * 
 * Produces PDF or CSV summaries of emergency requests
 * with statistics and data tables for Mobile Emergency Medical Assistance App.
 */
export class ReportGenerator {
  private static getPool(): Pool {
    return new Pool({
      connectionString: process.env.DATABASE_URL,
      ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
    });
  }

  /**
   * Creates a comprehensive report
   * 
   * @param options - Report generation options
   * 
   * @returns Promise resolving to report buffer
   */
  static async createReport(options: {
    from: Date;
    to: Date;
    format: 'pdf' | 'csv';
    includeCharts?: boolean;
    includeDetails?: boolean;
  }): Promise<Buffer> {
    try {
      // Get emergency requests data
      const requests = await EmergencyRequestRepository.findByDateRange(options.from, options.to);
      
      // Calculate statistics
      const stats = this.calculateStatistics(requests);
      
      if (options.format === 'csv') {
        return this.generateCSVReport(requests, stats, options);
      } else {
        return this.generatePDFReport(requests, stats, options);
      }
      
    } catch (error: any) {
      throw new Error(`Failed to generate report: ${error.message}`);
    }
  }

  /**
   * Calculates report statistics
   */
  private static calculateStatistics(requests: any[]) {
    const totalRequests = requests.length;
    
    // Calculate average response time
    const completedRequests = requests.filter(r => r.status === 'completed');
    const responseTimes = completedRequests
      .map(r => {
        const created = new Date(r.created_at);
        const accepted = new Date(r.accepted_at);
        return (accepted.getTime() - created.getTime()) / (1000 * 60); // minutes
      })
      .filter(time => time > 0);
    
    const averageResponseTime = responseTimes.length > 0
      ? responseTimes.reduce((sum, time) => sum + time, 0) / responseTimes.length
      : 0;

    // Calculate resolution rate
    const resolvedRequests = requests.filter(r => 
      r.status === 'completed' || r.status === 'cancelled'
    );
    const resolutionRate = totalRequests > 0
      ? (resolvedRequests.length / totalRequests) * 100
      : 0;

    // Group by type
    const requestsByType = requests.reduce((acc, request) => {
      acc[request.type] = (acc[request.type] || 0) + 1;
      return acc;
    }, {} as Record<string, number>);

    return {
      totalRequests,
      averageResponseTime,
      resolutionRate,
      requestsByType,
      generatedAt: new Date(),
    };
  }

  /**
   * Generates CSV report
   */
  private static async generateCSVReport(
    requests: any[],
    stats: any,
    options: any
  ): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      try {
        const csvWriter: any = csv.createObjectCsvStringifier({
          header: [
            'Request ID',
            'Patient ID',
            'Type',
            'Status',
            'Created At',
            'Accepted At',
            'Completed At',
            'Response Time (min)',
          ],
        });

        // Add data rows
        requests.forEach(request => {
          const responseTime = request.accepted_at
            ? ((new Date(request.accepted_at).getTime() - new Date(request.created_at).getTime()) / (1000 * 60)).toFixed(1)
            : 'N/A';

          csvWriter.writeRecords([
            request.id,
            request.user_id,
            request.type,
            request.status,
            request.created_at,
            request.accepted_at || 'N/A',
            request.completed_at || 'N/A',
            responseTime,
          ]);
        });

        // Add statistics summary
        csvWriter.writeRecords([]);
        csvWriter.writeRecords(['EMERGENCY REQUESTS REPORT']);
        csvWriter.writeRecords([`Generated: ${stats.generatedAt.toISOString()}`]);
        csvWriter.writeRecords([`Date Range: ${options.from.toISOString()} to ${options.to.toISOString()}`]);
        csvWriter.writeRecords([]);
        csvWriter.writeRecords(['SUMMARY STATISTICS']);
        csvWriter.writeRecords(['Total Requests', stats.totalRequests]);
        csvWriter.writeRecords(['Average Response Time (minutes)', stats.averageResponseTime.toFixed(2)]);
        csvWriter.writeRecords(['Resolution Rate (%)', stats.resolutionRate.toFixed(2)]);
        csvWriter.writeRecords([]);
        csvWriter.writeRecords(['REQUESTS BY TYPE']);
        
        Object.entries(stats.requestsByType).forEach(([type, count]) => {
          csvWriter.writeRecords([type, count]);
        });

        const csvString = csvWriter.toString();
        resolve(Buffer.from(csvString, 'utf-8'));
        
      } catch (error: any) {
        reject(error);
      }
    });
  }

  /**
   * Generates PDF report
   */
  private static async generatePDFReport(
    requests: any[],
    stats: any,
    options: any
  ): Promise<Buffer> {
    return new Promise((resolve, reject) => {
      try {
        const doc = new PDFDocument({ font: 'Helvetica' });
        
        // Add title
        doc.fontSize(20).text('Emergency Requests Report', { align: 'center' });
        doc.moveDown();
        
        // Add date range
        doc.fontSize(12).text(
          `Date Range: ${options.from.toLocaleDateString()} to ${options.to.toLocaleDateString()}`,
          { align: 'center' }
        );
        doc.moveDown();
        
        // Add summary statistics
        doc.fontSize(16).text('Summary Statistics', { underline: true });
        doc.moveDown();
        
        // Stats table
        const statsTableTop = 50;
        doc.fontSize(12).text(`Total Requests: ${stats.totalRequests}`, { continued: false });
        doc.text(`Average Response Time: ${stats.averageResponseTime.toFixed(2)} minutes`);
        doc.text(`Resolution Rate: ${stats.resolutionRate.toFixed(2)}%`);
        doc.moveDown();
        
        // Requests by type chart
        if (options.includeCharts) {
          doc.fontSize(16).text('Requests by Type', { underline: true });
          doc.moveDown();
          
          const chartData = Object.entries(stats.requestsByType).map(([type, count]) => ({
            label: type,
            value: count,
          }));
          
          // Simple bar chart visualization
          const maxCount = Math.max(...chartData.map(d => d.value as any));
          const barWidth = 400;
          const barHeight = 200;
          const chartStartX = 100;
          const chartStartY = doc.y;
          
          chartData.forEach((data, index) => {
            const h = ((data.value as any) / maxCount) * barHeight;
            const x = chartStartX + index * (barWidth / chartData.length);
            
            // Draw bar
            doc.rect(x, chartStartY, barWidth / chartData.length - 10, h).fill('#3B82F6');
            
            // Draw label
            doc.fontSize(10).fillColor('#666').text(data.label, {
              align: 'center',
              continued: false
            });
            
            // Draw value on top of bar
            doc.fontSize(8).fillColor('#333').text((data.value as any).toString(), {
              align: 'center',
              continued: false
            });
            
            doc.y = chartStartY + h + 20;
          });
          
          doc.y += barHeight + 60;
        }
        
        // Detailed requests table
        if (options.includeDetails) {
          doc.fontSize(16).text('Detailed Requests', { underline: true });
          doc.moveDown();
          
          // Table headers
          const headers = ['ID', 'Type', 'Status', 'Created', 'Response Time'];
          const columnWidths = [80, 100, 80, 120, 100];
          let xPos = 50;
          
          headers.forEach((header, index) => {
            doc.fontSize(10).text(header, { continued: false });
            xPos += columnWidths[index];
          });
          
          doc.moveDown();
          doc.moveTo(50, doc.y);
          
          // Table rows
          requests.slice(0, 50).forEach(request => {
            const responseTime = request.accepted_at
              ? ((new Date(request.accepted_at).getTime() - new Date(request.created_at).getTime()) / (1000 * 60)).toFixed(1)
              : 'N/A';
            
            xPos = 50;
            [request.id, request.type, request.status, 
             request.created_at?.split('T')[0], `${responseTime}min`].forEach((text, index) => {
              doc.fontSize(9).text(text, { continued: false });
              xPos += columnWidths[index];
            });
            
            doc.moveDown();
            doc.moveTo(50, doc.y);
          });
        }
        
        // Generate PDF buffer
        doc.end();
        const chunks: any[] = [];
        doc.on('data', chunk => chunks.push(chunk));
        doc.on('end', () => resolve(Buffer.concat(chunks)));
        
      } catch (error: any) {
        reject(error);
      }
    });
  }
}
