#!/usr/bin/env python3
"""
Measures average latency between two nodes over a specified time period.

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies: python3.10 or higher

VERSION 1.0.0
"""

import subprocess
import re
import time
import argparse
import sys
from statistics import mean, stdev


def ping_host(host, count=1, timeout=2):
    try:
        # Determine ping command based on OS
        if sys.platform.startswith('win'):
            cmd = ['ping', '-n', str(count), '-w', str(timeout * 1000), host]
        else:
            cmd = ['ping', '-c', str(count), '-W', str(timeout), host]
        
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout + 1
        )
        
        # Extract latency from ping output
        if sys.platform.startswith('win'):
            # Windows: time=XXms or time<1ms
            match = re.search(r'time[=<](\d+(?:\.\d+)?)ms', result.stdout)
        else:
            # Linux/Mac: time=XX.X ms
            match = re.search(r'time=(\d+(?:\.\d+)?)\s*ms', result.stdout)
        
        if match:
            return float(match.group(1))
        
        return None
        
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, ValueError):
        return None


def monitor_latency(source, target, duration_minutes=1, verbose=False):
    print(f"Monitoring latency from {source} to {target} for {duration_minutes} minute(s)...")
    print(f"Starting at: {time.strftime('%Y-%m-%d %H:%M:%S')}\n")
    
    if verbose:
        print(f"Platform: {sys.platform}")
        print(f"Ping interval: 1 second")
        print(f"Expected pings: ~{duration_minutes * 60}")
        print("-" * 60 + "\n")
    
    latencies = []
    failed_pings = 0
    start_time = time.time()
    end_time = start_time + (duration_minutes * 60)
    ping_interval = 1  # Ping every 1 second
    
    # Track running statistics for verbose mode
    running_avg = 0
    running_min = float('inf')
    running_max = 0
    
    try:
        while time.time() < end_time:
            ping_start = time.time()
            latency = ping_host(target)
            ping_duration = time.time() - ping_start
            
            if latency is not None:
                latencies.append(latency)
                running_avg = mean(latencies)
                running_min = min(running_min, latency)
                running_max = max(running_max, latency)
                
                if verbose:
                    time_remaining = int(end_time - time.time())
                    print(f"[{len(latencies):4d}] {time.strftime('%H:%M:%S')} | "
                          f"Latency: {latency:6.2f} ms | "
                          f"Avg: {running_avg:6.2f} ms | "
                          f"Min: {running_min:6.2f} ms | "
                          f"Max: {running_max:6.2f} ms | "
                          f"Remaining: {time_remaining:3d}s")
                else:
                    None
            else:
                failed_pings += 1
                if verbose:
                    time_remaining = int(end_time - time.time())
                    print(f"[{len(latencies) + failed_pings:4d}] {time.strftime('%H:%M:%S')} | "
                          f"Ping FAILED (timeout: {ping_duration:.2f}s) | "
                          f"Remaining: {time_remaining:3d}s")
                else:
                    print(f"[{len(latencies) + failed_pings}] Ping failed (timeout or unreachable)")
            
            # Wait for next ping, accounting for time spent pinging
            elapsed = time.time() - start_time
            next_ping = start_time + (len(latencies) + failed_pings) * ping_interval
            sleep_time = max(0, next_ping - time.time())
            time.sleep(sleep_time)
    
    except KeyboardInterrupt:
        print("\n\nMonitoring interrupted by user.")
    
    # Calculate statistics
    if latencies:
        stats = {
            'average': mean(latencies),
            'min': min(latencies),
            'max': max(latencies),
            'std_dev': stdev(latencies) if len(latencies) > 1 else 0,
            'total_pings': len(latencies) + failed_pings,
            'successful_pings': len(latencies),
            'failed_pings': failed_pings,
            'packet_loss': (failed_pings / (len(latencies) + failed_pings)) * 100
        }
        return stats
    else:
        return None


def main():
    parser = argparse.ArgumentParser(
        description='Monitor network latency between two nodes',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s localhost google.com
  %(prog)s myserver 8.8.8.8 --duration 3
  %(prog)s router1 192.168.1.1 -d 5
  %(prog)s localhost 8.8.8.8 -d 3 --verbose
        """
    )
    
    parser.add_argument(
        'source',
        help='Source node (local machine identifier)'
    )
    
    parser.add_argument(
        'target',
        help='Target node (hostname or IP address to ping)'
    )
    
    parser.add_argument(
        '-d', '--duration',
        type=int,
        choices=[1, 3, 5],
        default=1,
        help='Duration to monitor in minutes (default: 1)'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose mode with detailed real-time statistics'
    )
    
    args = parser.parse_args()
    
    # Run monitoring
    stats = monitor_latency(args.source, args.target, args.duration, args.verbose)
    
    # Display results
    print("\n" + "=" * 60)
    print("LATENCY STATISTICS")
    print("=" * 60)
    
    if stats:
        print(f"Source Node:        {args.source}")
        print(f"Target Node:        {args.target}")
        print(f"Duration:           {args.duration} minute(s)")
        print(f"\nTotal Pings:        {stats['total_pings']}")
        print(f"Successful:         {stats['successful_pings']}")
        print(f"Failed:             {stats['failed_pings']}")
        print(f"Packet Loss:        {stats['packet_loss']:.2f}%")
        print(f"\nAverage Latency:    {stats['average']:.2f} ms")
        print(f"Minimum Latency:    {stats['min']:.2f} ms")
        print(f"Maximum Latency:    {stats['max']:.2f} ms")
        print(f"Std Deviation:      {stats['std_dev']:.2f} ms")
    else:
        print("No successful pings recorded.")
        print(f"Target {args.target} may be unreachable or blocking ICMP packets.")
    
    print("=" * 60)


if __name__ == '__main__':
    main()