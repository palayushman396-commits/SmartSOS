const List<String> activeStatuses = [
  'initiated',
  'alert_sent',
  'responder_notified',
  'responder_assigned',
  'in_progress',
];

bool isTerminal(String status) => status == 'resolved' || status == 'cancelled';

String statusLabel(String status) {
  switch (status) {
    case 'initiated':
      return 'SOS initiated';
    case 'alert_sent':
      return 'Alert sent';
    case 'responder_notified':
      return 'Responder notified';
    case 'responder_assigned':
      return 'Responder assigned';
    case 'in_progress':
      return 'Assistance in progress';
    case 'resolved':
      return 'Resolved';
    case 'cancelled':
      return 'Cancelled';
    default:
      return status;
  }
}