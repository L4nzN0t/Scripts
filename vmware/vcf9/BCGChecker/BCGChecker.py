#!/usr/bin/env python3
"""
Search for the ESX hosts in Aria Operations and check whether they are compatible with ESX 9.0 in Broadcom Compatibility Guide

Author: Thomas Rodrigues (@L4nzN0t_)
Required Dependencies:  python3.10 or higher
                        install requirements

VERSION 1.0.0
"""
from colorama import Fore, Style, init
from tabulate import tabulate
from collections import defaultdict
from typing import Dict, List, Optional
from urllib.parse import urljoin
from os import path
from os import name as osname
import getpass
import csv
import json
import re
import argparse
import sys
import requests

init(autoreset=True)

def _print_banner():
    banner = r"""
 __     ______ _____    ___   ___                               
 \ \   / / ___|  ___|  / _ \ / _ \                              
  \ \ / / |   | |_    | (_) | | | |                             
   \ V /| |___|  _|    \__, | |_| |                             
   _\_/  \____|_|        /_(_)___/ _   _ _     _ _ _ _          
  / ___|___  _ __ ___  _ __   __ _| |_(_) |__ (_) (_) |_ _   _  
 | |   / _ \| '_ ` _ \| '_ \ / _` | __| | '_ \| | | | __| | | | 
 | |__| (_) | | | | | | |_) | (_| | |_| | |_) | | | | |_| |_| | 
  \____\___/|_| |_| |_| .__/ \__,_|\__|_|_.__/|_|_|_|\__|\__, | 
   ____ _             |_|                                |___/  
  / ___| |__   ___  ___| | _____ _ __                           
 | |   | '_ \ / _ \/ __| |/ / _ \ '__|                          
 | |___| | | |  __/ (__|   <  __/ |                             
  \____|_| |_|\___|\___|_|\_\___|_|                             
"""
    print(banner)
    print("\n")

class AriaOpsClient:
    """Client for interacting with Aria Operations API."""
    
    def __init__(self, host: str, username: str, domain: str, password: str, verify_ssl: bool = True):
        self.host = host.rstrip('/')
        self.url = f"https://{self.host}"
        self.session = requests.Session()
        self.verify_ssl = verify_ssl
        self.token = None
        self.username = username
        self.domain = domain
        self.password = password
    
    def authenticate(self):
        try:
            auth_url = f"{self.url}/suite-api/api/auth/token/acquire"
            json = {"username": self.username, "authSource" : self.domain, "password": self.password}
            headers = {"Content-Type": "application/json", "Accept": "application/json" }

            response = requests.post(url=auth_url, json=json, headers=headers, verify=self.verify_ssl)

            if response.status_code == 200:
                self.token = response.json().get("token")
                return True
            else:
                return False
        except Exception as e:
            print(e)
            return False
    
    def get_all_hosts(self) -> List[Dict]:
        """Retrieve all ESXi hosts from Aria Operations."""
        resources_url = f"{self.url}/suite-api/api/resources?page=0&pageSize=1000&resourceKind=hostSystem&_no_links=true"
        headers = {
            "Authorization": f"vRealizeOpsToken {self.token}",
            "Accept": "application/json"
        }
        try:
            response = self.session.get(resources_url,headers=headers, verify=self.verify_ssl)
            response.raise_for_status()
            data = response.json()
            return data.get('resourceList', [])
        except requests.exceptions.RequestException as e:
            print(f"[-] Error retrieving hosts: {e}")
            return []
    
    def get_resource_properties(self, resource_id: str) -> Dict:
        """Get properties for a specific resource."""
        properties_url = f"{self.url}/suite-api/api/resources/{resource_id}/properties?_no_links=true"
        headers = {
            "Authorization": f"vRealizeOpsToken {self.token}",
            "Accept": "application/json"
        }
        
        try:
            response = self.session.get(properties_url, headers=headers, verify=self.verify_ssl)
            response.raise_for_status()
            return response.json()
        except requests.exceptions.RequestException as e:
            print(f"[-] Error retrieving properties for {resource_id}: {e}")
            return {}
    
    def extract_server_models(self, hosts: List[Dict], verbose: bool = False) -> Dict[str, List[str]]:
        """Extract server models and their hostnames from host data."""
        servers = defaultdict(list)
        server_models = defaultdict(list)
        
        for host in hosts:
            resource_id = host.get('identifier')
            host_name = host.get('resourceKey', {}).get('name', 'Unknown')
            
            if verbose:
                print(f"[*] Processing host: {host_name}")
            
            # Get detailed properties
            properties = self.get_resource_properties(resource_id)
            property_list = properties.get('property', [])
            
            # Look for hardware model information
            # cpu|cpuModel
            # hardware|vendorModel
            # hardware|vendor
            
            hardware_model = False
            cpu_model = False
            for prop in property_list:
                prop_name = prop.get('name', '')
                
                if 'hardware|vendorModel' in prop_name:
                    hardware_model = prop.get('value')
                if 'hardware|vendor' in prop_name:
                    vendor = prop.get('value')
                if 'cpu|cpuModel' in prop_name:
                    cpu_model = prop.get('value')
                
                if hardware_model and cpu_model and vendor:
                    break
                
            if not hardware_model:
                hardware_model = 'Unknown'
                
            if not cpu_model:
                cpu_model = 'Unknown'
                
            
            servers[host_name].append({"vendor": vendor,"model": hardware_model, "cpu": cpu_model})
            server_models[hardware_model].append({"hostname": host_name, "cpu":cpu_model}) 
            if verbose:
                print(f"[*] Hardware Model: {hardware_model} - CPU {cpu_model}")
        
        return dict(servers), dict(server_models)
    
class VCFCompatibility:
    def __init__(self):
        self.DEFAULTVERSION = "ESXi 9.0"
        self.base_url = "https://compatibilityguide.broadcom.com/compguide/programs/viewResults?limit=20&page=1&sortBy=partnerName&sortType=ASC"
    
    def color_compat(self, compat_list):
        value = compat_list
        if len(compat_list) > 1:
            if "ESXi 9.0" in value:
                colored_lines = [f"{Fore.GREEN}{line}{Style.RESET_ALL}" for line in compat_list]
                compat_str = "\n".join(colored_lines)
                return compat_str
            elif value == "Not Found":
                colored_lines = [f"{Fore.WHITE}{line}{Style.RESET_ALL}" for line in compat_list]
                compat_str = "\n".join(colored_lines)
                return compat_str
            elif value == "Not Applied":
                colored_lines = [f"{Fore.YELLOW}{line}{Style.RESET_ALL}" for line in compat_list]
                compat_str = "\n".join(colored_lines)
                return compat_str
            else:
                colored_lines = [f"{Fore.RED}{line}{Style.RESET_ALL}" for line in compat_list]
                compat_str = "\n".join(colored_lines)
                return compat_str
        elif len(compat_list) == 1:
            value = compat_list[0]
            if "ESXi 9.0" in value:
                return f"{Fore.GREEN}{value}{Style.RESET_ALL}"
            elif value == "Not Found":
                return f"{Fore.WHITE}{value}{Style.RESET_ALL}"
            elif value == "Not Applied":
                return f"{Fore.YELLOW}{value}{Style.RESET_ALL}"
            else:
                return f"{Fore.RED}{value}{Style.RESET_ALL}"
        else:
            value = "Not Found"
            return f"{Fore.WHITE}{value}{Style.RESET_ALL}"
    
    def print_table(self, title, table, headers, style: Optional[str] = "simple_grid"):
        if not table:
            return

        print(f"\n{title}")
        print("=" * len(title))
        print(tabulate(table,headers=headers,tablefmt=style))
        
    def check_vcf_compatibility(self, server_models: dict):
        
        for key in server_models:
            if 'vmware' in key.lower() or 'amazon' in key.lower():
                for value in server_models[key]:
                    value.update({"compatibility": ["Not Applied"]})
                continue
            
            # Define the CPU family of each server 
            temp_cpus = set(server['cpu'] for server in server_models[key])
            temp_cpus = list(temp_cpus)
            cpus = []
            for cpu in temp_cpus:
                cleaned = re.sub(r'\([^)]*\)', '', cpu)
                cleaned = re.sub(r'@.*$', '', cleaned)  
                cleaned = ' '.join(cleaned.split())
                cpus.append(cleaned)
            
            cpu_family = []
            if len(cpus) <= 1:
                match = re.search(r'(Gold|Silver|Platinum)\s+(\d{2})', cpu)
                
                if match:
                    series = match.group(1)
                    family = match.group(2)
                    cpu_family.append(f"Intel Xeon {series} {family}")
                else:
                    cpu_family.append('')
            else:
                for cpu in cpus:
                    match = re.search(r'(Gold|Silver|Platinum)\s+(\d{2})', cpu)
                    if match:
                        series = match.group(1)
                        family = match.group(2)
                        cpu_family.append(f"Intel Xeon {series} {family}")
                    else:
                        continue
            
            # Define model and vendor for url search
            words = key.split()
            vendor = " ".join(words[:2])
            model = " ".join(words[2:])
            
            if 'dell' in vendor.lower():
                vendor = 'Dell'
            
            if 'hp' in vendor.lower() :
                vendor = 'Hewlett Packard Enterprise'
            
            payload = {
                "programId":"server",
                "filters": [
                    {
                        "displayKey":"partnerName",
                        "filterValues":[vendor]
                    }
                ],
                "keyword": [model],
                "date": {
                    "startDate":"",
                    "endDate":""
                }
            }
            
            try:
                headers = { "Content-Type": "application/json"}
                response = requests.post(self.base_url,json=payload,headers=headers)
                response.raise_for_status()
                jsondump = json.loads(response.text)
                
                if jsondump['data']['count'] == 0:
                    for value in server_models[key]:
                        value.update({"compatibility": ["Not Found"]})
                else:
                    for item in jsondump['data']['fieldValues']:
                        if 'cpuSeries' in item:
                            for cpu in item['cpuSeries']:
                                for cpu_to_search in cpu_family:
                                    search_words = cpu_to_search.lower().split()
                                    cpu_name = cpu['name'].lower()
                                    if all(word in cpu_name for word in search_words):
                                    # get esxi version
                                        esxi_list = [esxi['name'] for esxi in item['supportedReleases']]
                                        for value in server_models[key]:
                                            value.update({"compatibility": esxi_list})
                                        break  
                                    else:
                                        for value in server_models[key]:
                                            if(value.get('compatibility')):
                                                break
                                            else:
                                                value.update({"compatibility": "Not Found"})                   
            except requests.exceptions.RequestException as e:
                print(f"[-] Error retrieving properties {e}")
                return {} 
            except Exception as e:
                print(f"[-] Runtime error {e}")
                return {}     
        
        return server_models
    
    def export_data(self, data, filename="server_export.csv"):
        script_dir = path.dirname(__file__)
        if osname == 'nt':
            filename = script_dir + "\\" + filename
        elif osname == 'posix':
            filename = script_dir + "/" + filename
        
        with open(filename, 'w', newline='', encoding='utf-8') as f:
            writer = csv.writer(f)
            
            # Write header
            writer.writerow(['Hostname', 'Model', 'CPU', 'Compatibility'])
            
            # Write data
            for server_model, items in data.items():
                for item in items:
                    hostname = item['hostname']
                    cpu = item['cpu']
                    # Join compatibility list into a single string
                    compatibility = ', '.join(item['compatibility']) if isinstance(item['compatibility'], list) else item['compatibility']
                    
                    writer.writerow([hostname, server_model, cpu, compatibility])
        
        print("\n")
        print(f"{Fore.GREEN}[+] Data exported to {filename}{Style.RESET_ALL}")
    
    
def main():
    parser = argparse.ArgumentParser(
        description='Check VCF 9 compatibility for servers in Aria Operations',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --host aria.example.com --username admin --password pass123 --domain LOCAL
  %(prog)s -H aria.example.com -u admin -p pass123 -d domain.com --verbose
  %(prog)s -H aria.example.com -u admin -p pass123 --domain domain.com --no-verify-ssl
        """
    )
    
    parser.add_argument(
        '-H', '--host',
        required=False,
        help='Aria Operations hostname or IP'
    )
    parser.add_argument(
        '-u', '--username',
        required=False,
     
        help='Aria Operations username'
    )
    parser.add_argument(
        '-d', '--domain',
        required=False,
        help='Aria Operations domain'
    )
    parser.add_argument(
        '-p', '--password',
        required=False,
        help='Aria Operations password'
    )
    parser.add_argument(
        '--no-verify-ssl',
        action='store_true',
        help='Disable SSL certificate verification'
    )
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    parser.add_argument(
        '-o', '--output',
        help='Output results to csv file'
    )
    
    args = parser.parse_args()
    
    # Suppress SSL warnings if verification is disabled
    if args.no_verify_ssl:
        import urllib3
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    
    if not args.password:
        args.password = getpass.getpass("Enter password: ")
    
    print("[*] Connecting to Aria Operations...")
    aria_client = AriaOpsClient(
        args.host,
        args.username,
        args.domain,
        args.password,
        verify_ssl=not args.no_verify_ssl
    )
    
    # Try to authenticate
    if not aria_client.authenticate():
        print(f"{Fore.RED}[-] Failed to authenticate with Aria Operations.")
        sys.exit(1)
    print(f"{Fore.GREEN}[+] Authentication successful!")
    print("[*] Retrieving server information from Aria Operations...")
    
    # Search for hosts
    hosts = aria_client.get_all_hosts()
    print(f"[*] Found {len(hosts)} hosts.")
    
    # Extract server models
    print("[*] Extracting server models...")
    servers, server_models = aria_client.extract_server_models(hosts, args.verbose)
    server_models = dict(sorted(server_models.items()))
    print(f"[*] Found {len(server_models)} unique server models.")
    
    # New instance VCFCompatibility class
    compatibility_client = VCFCompatibility()
    
    if args.verbose:
        # Output the Model list
        i = 1
        table = []
        for key in server_models:
            table.append([i, key, len(server_models[key])])
            i += 1
        headers = ["#", "Server Model", "Quantity"]
        compatibility_client.print_table("[*] MODEL LIST", table, headers)
    
        # Output the models totals
        table = [["#", len(server_models), len(servers)]]
        headers = ["#", "Server Model", "Quantity"]
        compatibility_client.print_table("[*] TOTAL", table, headers)
    
    # Return compatibility of each host
    compatibility_client.check_vcf_compatibility(server_models)
    
    # Prepare table for output
    table = []
    idx = 1
    headers = ["#", "Server Model", "CPU", "Quantity", "Compatibility"]
    for key in server_models:
        for item in server_models[key]:
            cpu_data = defaultdict(lambda: {"count": 0, "compatibility": set()})
            
            for item in server_models[key]:
                cpu = item["cpu"]
                cpu_data[cpu]["count"] += 1
                
                if isinstance(item['compatibility'], list):
                    cpu_data[cpu]["compatibility"].update(item['compatibility'])
                else:
                    cpu_data[cpu]["compatibility"].add(item['compatibility'])
                
        for cpu, data in cpu_data.items():
            # Convert set to sorted list
            compat_list = sorted(data["compatibility"])
                
            table.append([
                idx,
                key,
                cpu,
                data["count"],
                compatibility_client.color_compat(compat_list)
            ])
            idx += 1 
            
    # Output the summary
    compatibility_client.print_table("[*] SUMMARY", table, headers,"fancy_grid")
    
    # Prepare detailed output
    vcf9 = {}
    notcompatible = {}
    notapplied = {}
    notfound = {}
    for key in server_models:
        vcf9[key] = []
        notcompatible[key] = []
        notapplied[key] = []
        notfound[key] = []
        
        for item in server_models[key]:
            if 'Not Applied' in item.get('compatibility'):
                notapplied[key].append(item)
            elif 'Not Found' in item.get('compatibility'):
                notfound[key].append(item)
            elif 'ESXi 9.0' in item.get('compatibility', []):
                vcf9[key].append(item)
            else:
                notcompatible[key].append(item)

        # Remove empty lists
        if not notapplied[key]:
            del notapplied[key]
        if not notfound[key]:
            del notfound[key]
        if not notcompatible[key]:
            del notcompatible[key]
        if not vcf9[key]:
            del vcf9[key]
    
    if args.verbose:
        # Output detailed results
        table = []
        headers = ["#", "Model", "Quantity"]
        table = []
        for key in notapplied:
            table.append([i, key, len(notapplied[key])])
            i += 1
        compatibility_client.print_table("NOT APPLIED", table, headers)
        
        table.clear()
        for key in notfound:
            table.append([i, key, len(notfound[key])])
            i += 1
        compatibility_client.print_table("NOT FOUND", table, headers)
        
        table.clear()
        for key in notcompatible:
            table.append([i, key, len(notcompatible[key])])
            i += 1
        compatibility_client.print_table("NOT COMPATIBLE", table, headers)
        
        table.clear()
        for key in vcf9:
            table.append([i, key, len(vcf9[key])])
            i += 1
        compatibility_client.print_table("VCF 9 COMPATIBLE SERVERS", table, headers)
    
    # Summary Totals
    total_vcf9 = sum(len(v) for v in vcf9.values())
    total_notapplied = sum(len(v) for v in notapplied.values())
    total_notcompatible = sum(len(v) for v in notcompatible.values())
    total_notfound = sum(len(v) for v in notfound.values())
    
    headers = ["VCF 9.0", "NOT COMPATIBLE", "NOT FOUND", "NOT APPLIED"]
    table = [[total_vcf9, total_notcompatible, total_notfound, total_notapplied]]
    compatibility_client.print_table("[*] TOTAL SUMMARY", table, headers,"fancy_grid")
    
    # Export data
    if args.output:
        compatibility_client.export_data(server_models, args.output)
    else:
        compatibility_client.export_data(server_models)
    
if __name__ == '__main__':
    _print_banner()
    main()