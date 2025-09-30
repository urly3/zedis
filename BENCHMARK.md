# Zedis vs Redis Benchmark Results

## Test Environment
- **Hardware**: MacBook Pro M4
- **Command**: `redis-benchmark -h 127.0.0.1 -p 6379 -t get,set -n 1000 -c 100`

---

## Performance Comparison

| Metric              | Zedis        | Redis        | Improvement |
| ------------------- | ------------ | ------------ | ----------- |
| **SET Throughput**  | 62,500 req/s | 76,923 req/s | -18.7%      |
| **GET Throughput**  | 83,333 req/s | 76,923 req/s | +8.3%       |
| **SET Avg Latency** | 1.214 ms     | 1.057 ms     | -14.9%      |
| **GET Avg Latency** | 1.050 ms     | 0.999 ms     | -5.1%       |
| **SET P95 Latency** | 2.631 ms     | 3.127 ms     | +15.9%      |
| **GET P95 Latency** | 1.223 ms     | 1.559 ms     | +21.6%      |

---

## Detailed Results

### Zedis

#### SET Command
```
1000 requests completed in 0.02 seconds
100 parallel clients
3 bytes payload
keep alive: 1
multi-thread: no
```

**Latency Summary (ms)**:
| Metric | Value |
| ------ | ----- |
| avg    | 1.214 |
| min    | 0.168 |
| p50    | 1.039 |
| p95    | 2.631 |
| p99    | 3.575 |
| max    | 4.551 |

**Throughput**: 62,500 requests per second

<details>
<summary>Latency by percentile distribution</summary>

```
0.000% <= 0.175 milliseconds (cumulative count 1)
50.000% <= 1.039 milliseconds (cumulative count 509)
75.000% <= 1.271 milliseconds (cumulative count 758)
87.500% <= 1.751 milliseconds (cumulative count 875)
93.750% <= 2.527 milliseconds (cumulative count 938)
96.875% <= 2.791 milliseconds (cumulative count 974)
98.438% <= 3.039 milliseconds (cumulative count 986)
99.219% <= 4.063 milliseconds (cumulative count 993)
99.609% <= 4.295 milliseconds (cumulative count 997)
99.805% <= 4.519 milliseconds (cumulative count 999)
99.902% <= 4.551 milliseconds (cumulative count 1000)
100.000% <= 4.551 milliseconds (cumulative count 1000)
```
</details>

<details>
<summary>Cumulative distribution of latencies</summary>

```
0.000% <= 0.103 milliseconds (cumulative count 0)
0.200% <= 0.207 milliseconds (cumulative count 2)
1.100% <= 0.303 milliseconds (cumulative count 11)
1.700% <= 0.407 milliseconds (cumulative count 17)
2.600% <= 0.503 milliseconds (cumulative count 26)
4.000% <= 0.607 milliseconds (cumulative count 40)
11.300% <= 0.703 milliseconds (cumulative count 113)
19.600% <= 0.807 milliseconds (cumulative count 196)
29.700% <= 0.903 milliseconds (cumulative count 297)
43.600% <= 1.007 milliseconds (cumulative count 436)
57.600% <= 1.103 milliseconds (cumulative count 576)
69.100% <= 1.207 milliseconds (cumulative count 691)
77.500% <= 1.303 milliseconds (cumulative count 775)
81.600% <= 1.407 milliseconds (cumulative count 816)
85.000% <= 1.503 milliseconds (cumulative count 850)
87.100% <= 1.607 milliseconds (cumulative count 871)
87.300% <= 1.703 milliseconds (cumulative count 873)
87.600% <= 1.807 milliseconds (cumulative count 876)
87.900% <= 1.903 milliseconds (cumulative count 879)
88.200% <= 2.007 milliseconds (cumulative count 882)
88.300% <= 2.103 milliseconds (cumulative count 883)
98.700% <= 3.103 milliseconds (cumulative count 987)
99.300% <= 4.103 milliseconds (cumulative count 993)
100.000% <= 5.103 milliseconds (cumulative count 1000)
```
</details>

#### GET Command
```
1000 requests completed in 0.01 seconds
100 parallel clients
3 bytes payload
keep alive: 1
multi-thread: no
```

**Latency Summary (ms)**:
| Metric | Value |
| ------ | ----- |
| avg    | 1.050 |
| min    | 0.576 |
| p50    | 1.087 |
| p95    | 1.223 |
| p99    | 1.263 |
| max    | 1.431 |

**Throughput**: 83,333 requests per second

<details>
<summary>Latency by percentile distribution</summary>

```
0.000% <= 0.583 milliseconds (cumulative count 1)
50.000% <= 1.087 milliseconds (cumulative count 524)
75.000% <= 1.159 milliseconds (cumulative count 768)
87.500% <= 1.191 milliseconds (cumulative count 898)
93.750% <= 1.215 milliseconds (cumulative count 949)
96.875% <= 1.231 milliseconds (cumulative count 970)
98.438% <= 1.255 milliseconds (cumulative count 987)
99.219% <= 1.279 milliseconds (cumulative count 993)
99.609% <= 1.327 milliseconds (cumulative count 997)
99.805% <= 1.351 milliseconds (cumulative count 999)
99.902% <= 1.431 milliseconds (cumulative count 1000)
100.000% <= 1.431 milliseconds (cumulative count 1000)
```
</details>

<details>
<summary>Cumulative distribution of latencies</summary>

```
0.000% <= 0.103 milliseconds (cumulative count 0)
0.800% <= 0.607 milliseconds (cumulative count 8)
2.400% <= 0.703 milliseconds (cumulative count 24)
6.700% <= 0.807 milliseconds (cumulative count 67)
18.200% <= 0.903 milliseconds (cumulative count 182)
27.600% <= 1.007 milliseconds (cumulative count 276)
55.400% <= 1.103 milliseconds (cumulative count 554)
93.400% <= 1.207 milliseconds (cumulative count 934)
99.500% <= 1.303 milliseconds (cumulative count 995)
99.900% <= 1.407 milliseconds (cumulative count 999)
100.000% <= 1.503 milliseconds (cumulative count 1000)
```
</details>

---

### Redis

#### SET Command
```
1000 requests completed in 0.01 seconds
100 parallel clients
3 bytes payload
keep alive: 1
host configuration "save": 3600 1 300 100 60 10000
host configuration "appendonly": no
multi-thread: no
```

**Latency Summary (ms)**:
| Metric | Value |
| ------ | ----- |
| avg    | 1.057 |
| min    | 0.448 |
| p50    | 0.855 |
| p95    | 3.127 |
| p99    | 3.479 |
| max    | 3.591 |

**Throughput**: 76,923 requests per second

<details>
<summary>Latency by percentile distribution</summary>

```
0.000% <= 0.455 milliseconds (cumulative count 1)
50.000% <= 0.855 milliseconds (cumulative count 505)
75.000% <= 0.911 milliseconds (cumulative count 766)
87.500% <= 0.943 milliseconds (cumulative count 885)
93.750% <= 3.031 milliseconds (cumulative count 938)
96.875% <= 3.295 milliseconds (cumulative count 970)
98.438% <= 3.431 milliseconds (cumulative count 985)
99.219% <= 3.511 milliseconds (cumulative count 993)
99.609% <= 3.551 milliseconds (cumulative count 997)
99.805% <= 3.575 milliseconds (cumulative count 999)
99.902% <= 3.591 milliseconds (cumulative count 1000)
100.000% <= 3.591 milliseconds (cumulative count 1000)
```
</details>

<details>
<summary>Cumulative distribution of latencies</summary>

```
0.000% <= 0.103 milliseconds (cumulative count 0)
0.800% <= 0.503 milliseconds (cumulative count 8)
4.400% <= 0.607 milliseconds (cumulative count 44)
9.200% <= 0.703 milliseconds (cumulative count 92)
27.100% <= 0.807 milliseconds (cumulative count 271)
73.200% <= 0.903 milliseconds (cumulative count 732)
90.000% <= 1.007 milliseconds (cumulative count 900)
94.700% <= 3.103 milliseconds (cumulative count 947)
100.000% <= 4.103 milliseconds (cumulative count 1000)
```
</details>

#### GET Command
```
1000 requests completed in 0.01 seconds
100 parallel clients
3 bytes payload
keep alive: 1
host configuration "save": 3600 1 300 100 60 10000
host configuration "appendonly": no
multi-thread: no
```

**Latency Summary (ms)**:
| Metric | Value |
| ------ | ----- |
| avg    | 0.999 |
| min    | 0.632 |
| p50    | 0.951 |
| p95    | 1.559 |
| p99    | 1.679 |
| max    | 1.703 |

**Throughput**: 76,923 requests per second

<details>
<summary>Latency by percentile distribution</summary>

```
0.000% <= 0.639 milliseconds (cumulative count 2)
50.000% <= 0.951 milliseconds (cumulative count 505)
75.000% <= 1.111 milliseconds (cumulative count 755)
87.500% <= 1.319 milliseconds (cumulative count 876)
93.750% <= 1.543 milliseconds (cumulative count 941)
96.875% <= 1.631 milliseconds (cumulative count 969)
98.438% <= 1.663 milliseconds (cumulative count 985)
99.219% <= 1.687 milliseconds (cumulative count 995)
99.609% <= 1.703 milliseconds (cumulative count 1000)
100.000% <= 1.703 milliseconds (cumulative count 1000)
```
</details>

<details>
<summary>Cumulative distribution of latencies</summary>

```
0.000% <= 0.103 milliseconds (cumulative count 0)
8.700% <= 0.703 milliseconds (cumulative count 87)
24.900% <= 0.807 milliseconds (cumulative count 249)
37.200% <= 0.903 milliseconds (cumulative count 372)
61.600% <= 1.007 milliseconds (cumulative count 616)
73.700% <= 1.103 milliseconds (cumulative count 737)
83.300% <= 1.207 milliseconds (cumulative count 833)
86.700% <= 1.303 milliseconds (cumulative count 867)
90.800% <= 1.407 milliseconds (cumulative count 908)
92.700% <= 1.503 milliseconds (cumulative count 927)
96.400% <= 1.607 milliseconds (cumulative count 964)
100.000% <= 1.703 milliseconds (cumulative count 1000)
```
</details>