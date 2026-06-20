#!/usr/bin/env python3
"""
QCOW2 Hole Puncher

Usage:
    python3 qcow2_punch.py <qcow2_file> [--analyze|--punch]
"""

import os
import sys
import ctypes
import argparse
from stat import ST_SIZE

# QCOW2 Constants
QCOW_MAGIC = 0x514649FB
HEADER_SIZE = 72

# Fallocate flags (Linux)
FALLOC_FL_PUNCH_HOLE = 0x04
FALLOC_FL_KEEP_SIZE = 0x01

def format_bytes(size):
    """Format bytes to human readable"""
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(size) < 1024.0:
            return f"{size:.2f} {unit}"
        size /= 1024.0
    return f"{size:.2f} PB"

class QCOW2Image:
    def __init__(self, filepath):
        self.filepath = filepath
        with open(filepath, 'rb') as f:
            header = f.read(128)
            
            magic = int.from_bytes(header[0:4], 'big')
            if magic != QCOW_MAGIC:
                raise ValueError(f"Invalid QCOW magic: 0x{magic:08X}")
            
            self.version = int.from_bytes(header[4:8], 'big')
            self.backing_offset = int.from_bytes(header[8:16], 'big')
            
            # v3 header: offset 16-23 is L2 table size + cluster bits
            self.l2_table_size = int.from_bytes(header[16:20], 'big')
            self.cluster_bits = int.from_bytes(header[20:24], 'big')
            
            # v3 header: offset 24-31 is cluster size + page size
            self.cluster_size_raw = int.from_bytes(header[24:28], 'big')
            self.page_size = int.from_bytes(header[28:32], 'big')
            
            # Virtual disk size at offset 24! (in the cluster size field for v3)
            self.virtual_size = int.from_bytes(header[24:32], 'big')
            
            # If virtual size is 0 or too small, try other offsets
            if self.virtual_size < 1024:
                # Try offset 32-39
                self.virtual_size = int.from_bytes(header[32:40], 'big')
            
            # Calculate cluster size
            if self.cluster_size_raw > 0:
                self.cluster_size = self.cluster_size_raw
            else:
                self.cluster_size = 1 << self.cluster_bits
            
            # L1 table and refcount table offsets
            if self.version == 3:
                self.l1_offset = int.from_bytes(header[40:48], 'big')
                self.refcount_offset = int.from_bytes(header[48:56], 'big')
            else:
                self.l1_offset = int.from_bytes(header[24:32], 'big')
                self.refcount_offset = int.from_bytes(header[32:40], 'big')
            
            self.file_size = os.stat(filepath)[ST_SIZE]
            
            if self.cluster_size > 0:
                self.total_clusters = self.virtual_size // self.cluster_size
            else:
                self.total_clusters = 0
            
    def __repr__(self):
        return f"QCOW2(v{self.version}, virtual={format_bytes(self.virtual_size)}, file={format_bytes(self.file_size)})"

def analyze_image(filepath):
    """Analyze QCOW2 image"""
    img = QCOW2Image(filepath)
    
    print("🔍 QCOW2 Image Analysis")
    print("=" * 50)
    print(f"File:          {img.filepath}")
    print(f"Version:       QCOW{img.version}")
    print(f"Virtual Size:  {format_bytes(img.virtual_size)}")
    print(f"File Size:     {format_bytes(img.file_size)}")
    print(f"Cluster Size:  {img.cluster_size:,} bytes")
    print(f"Total Clusters: {img.total_clusters:,}")
    print(f"L1 Offset:     {img.l1_offset:,}")
    print(f"Refcount Off:  {img.refcount_offset:,}")
    print()
    
    # Calculate metadata size
    metadata_end = max(img.l1_offset, img.refcount_offset)
    if metadata_end > 0:
        metadata_size = metadata_end + (img.total_clusters * 8)
    else:
        metadata_size = img.file_size
    
    allocated = min(img.file_size, metadata_end) if metadata_end > 0 else img.file_size
    
    print("💾 Space Analysis:")
    print(f"  File Size:      {format_bytes(img.file_size)}")
    print(f"  Virtual Size:   {format_bytes(img.virtual_size)}")
    print(f"  Metadata Size:  ~{format_bytes(metadata_size)}")
    print(f"  Data Clusters:  ~{format_bytes(img.virtual_size - metadata_size)}")
    print()
    
    if img.file_size < img.virtual_size * 0.1:
        print("✅ Image is already highly sparse")
    elif img.file_size < img.virtual_size * 0.5:
        print("📊 Image has moderate compression")
    else:
        savings = img.virtual_size - img.file_size
        print(f"📉 Potential savings: ~{format_bytes(savings)}")
    
    return img

def punch_holes(filepath):
    """Punch holes in zero clusters"""
    img = QCOW2Image(filepath)
    
    print()
    print("🔨 Punching holes...")
    print("=" * 50)
    
    # Check fallocate support
    try:
        libc = ctypes.CDLL("libc.so.6", use_errno=True)
        has_fallocate = hasattr(libc, 'fallocate')
    except:
        has_fallocate = False
    
    if not has_fallocate:
        print("⚠️  fallocate not available")
    
    initial_size = img.file_size
    cluster_size = img.cluster_size
    
    # Data starts after header + L1 + refcount tables
    # Rough estimate based on cluster count
    metadata_clusters = (img.total_clusters // 1024) + 1 if img.total_clusters > 0 else 256
    data_start = img.cluster_size * metadata_clusters
    
    print(f"Cluster size:   {format_bytes(cluster_size)}")
    print(f"Total clusters: {img.total_clusters:,}")
    print(f"Data starts:   {format_bytes(data_start)}")
    print()
    
    zero_clusters = 0
    bytes_punched = 0
    
    with open(filepath, 'r+b') as f:
        for i in range(int(img.total_clusters)):
            offset = i * cluster_size
            
            if offset < data_start:
                continue
            
            # Read first 4KB to check if zero
            f.seek(offset)
            data = f.read(4096)
            
            if data and all(b == 0 for b in data):
                zero_clusters += 1
                
                if has_fallocate:
                    try:
                        result = libc.fallocate(
                            f.fileno(),
                            FALLOC_FL_PUNCH_HOLE | FALLOC_FL_KEEP_SIZE,
                            offset,
                            cluster_size
                        )
                        if result == 0:
                            bytes_punched += cluster_size
                    except:
                        pass
            
            if i % 10000 == 0 and i > 0:
                pct = i / img.total_clusters * 100
                print(f"\r  {pct:6.1f}% | Zero: {zero_clusters:,} | Punched: {format_bytes(bytes_punched)}   ", end='', flush=True)
    
    print()
    print()
    
    final_size = os.stat(filepath)[ST_SIZE]
    actual_saved = initial_size - final_size
    
    print("✅ Complete!")
    print("=" * 50)
    print(f"Zero clusters: {zero_clusters:,}")
    print(f"Bytes punched: {format_bytes(bytes_punched)}")
    print(f"Before:       {format_bytes(initial_size)}")
    print(f"After:        {format_bytes(final_size)}")
    print(f"Saved:        {format_bytes(max(0, actual_saved))}")
    print()
    
    if actual_saved > 0:
        print(f"🎉 Saved {format_bytes(actual_saved)}!")
    elif bytes_punched > 0:
        print("ℹ️  Holes punched but filesystem doesn't support punch hole")

def main():
    parser = argparse.ArgumentParser(description='QCOW2 Hole Puncher')
    parser.add_argument('file', help='QCOW2 file')
    parser.add_argument('--punch', '-p', action='store_true', help='Punch holes')
    
    args = parser.parse_args()
    
    if not os.path.exists(args.file):
        print(f"Error: File not found")
        sys.exit(1)
    
    try:
        if args.punch:
            punch_holes(args.file)
        else:
            analyze_image(args.file)
            print()
            print("Run with --punch to reclaim space")
    except Exception as e:
        print(f"Error: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == '__main__':
    main()
