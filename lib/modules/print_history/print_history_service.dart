import '../../shared/models/print_job_model.dart';
import '../print_queue/print_job_repository.dart';

/// Provides search, filtering, and analytics over historical print jobs.
class PrintHistoryService {
  final PrintJobRepository repository;

  const PrintHistoryService(this.repository);

  List<PrintJobModel> queryHistory({
    String? searchQuery,
    String? printerId,
    PrintJobStatus? status,
    String? copyType,
    int limit = 250,
  }) {
    return repository.listJobs(
      statuses: status != null ? [status] : null,
      printerId: printerId,
      searchBillNumber: searchQuery,
      copyType: copyType,
      limit: limit,
    );
  }
}
