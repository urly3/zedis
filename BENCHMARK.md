# Zedis vs Redis Benchmark Results

## Test Environment
- **Hardware**: MacBook Pro M4
- **Command**: `redis-benchmark -h 127.0.0.1 -p 6379 -t get,set -n 1000 -c 80`

## Results Summary

### Zedis
- **Throughput**: 66,666.67 requests per second
- **Latency (msec)**:
  | Metric | Value |
  | ------ | ----- |
  | avg    | 1.128 |
  | min    | 0.152 |
  | p50    | 1.159 |
  | p95    | 2.023 |
  | p99    | 5.031 |
  | max    | 6.071 |

### Redis
- **Throughput**: 43,478.26 requests per second
- **Latency (msec)**:
  | Metric | Value |
  | ------ | ----- |
  | avg    | 1.763 |
  | min    | 0.840 |
  | p50    | 1.663 |
  | p95    | 2.439 |
  | p99    | 2.479 |
  | max    | 2.495 |

## Performance Comparison
- **Throughput**: Zedis is **53.3% faster** than Redis (66,666.67 vs 43,478.26 requests/sec)
- **Average Latency**: Zedis is **36.0% faster** than Redis (1.128ms vs 1.763ms)