import requests
import urllib3
from os import path
import sys
import argparse

class AriaOperationsAPI():

    def __init__(self, host, username, password, domain, verify_ssl=False):
        self.url = f"https://{host}"
        self.username = username
        self.password = password
        self.domain = domain
        self.verify_ssl = verify_ssl
        self.token = None
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        
    def get_token(self):
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
    
    def get_vcenter_adapters(self):
        try:
            adapter_kind_url = f"{self.url}/suite-api/api/adapterkinds"
            headers = { "Authorization": f"OpsToken {self.token}", "Accept": "application/json" }
            response = requests.get(url=adapter_kind_url,headers=headers,verify=self.verify_ssl)
            if response.status_code == 200:
                adapters_kind = response.json().get("adapter-kind", [])
                for adapter in adapters_kind:
                    if adapter.get("name") == "vCenter":
                        vcenter_adapter_kind = adapter.get("key")
                        break
                
            adapter_url = f"{self.url}/suite-api/api/adapters"
            params = {"adapterKindKey": vcenter_adapter_kind}
            response2 = requests.get(url=adapter_url,headers=headers,params=params,verify=self.verify_ssl)
            if response2.status_code == 200:
                adapters = response2.json().get("adapterInstancesInfoDto", [])
                return adapters
            else:
                raise Exception("Error getting vCenter resources") 
               
        except Exception as e:
            print(e)
            return []
            
    def extract_vcenter_fqdns(self):
        fqdns = []
        
        adapters_list = self.get_vcenter_adapters()
        for adapter in adapters_list:
            vc_name = adapter.get("resourceKey").get("name")
            for type in adapter.get('resourceKey').get("resourceIdentifiers"):
                if type.get("identifierType").get("name") == "VCURL":
                    vc_fqdn = type.get("value")
                
                if type.get("identifierType").get("name") == "VMEntityVCID":
                    vc_id = type.get("value")
                    break
        
            fqdns.append({"name": vc_name, "fqdn": vc_fqdn, "vcenterID": vc_id })
            
        return fqdns
    
    
#################################################################################################
##################################### SCRIPT EXECUTION ##########################################

def main():
    """Main function to run the script"""
    parser = argparse.ArgumentParser(description="Get vCenter FQDNs from Aria Operations Manager")
    parser.add_argument("--host", required=True, help="Aria Operations Manager hostname or IP")
    parser.add_argument("--username", required=True, help="Username for authentication")
    parser.add_argument("--domain", required=True, help="Domain for user authentication")
    parser.add_argument("--password", required=True, help="Password for authentication")
    parser.add_argument("--insecure", action="store_true", help="Skip SSL verification")
    parser.add_argument("--output", required=True, help="Output file")
    
    args = parser.parse_args()
    
    client = AriaOperationsAPI(
        host = args.host,
        username = args.username,
        password = args.password,
        domain = args.domain,
        verify_ssl = not args.insecure
    )
    
    if not client.get_token():
        sys.exit(1)
    
    vcenter_list = client.extract_vcenter_fqdns()
    
    script_path = path.abspath(__file__)
    script_dir = path.dirname(script_path)
    file_out = f"{script_dir}\\{args.output}"
    
    with open(file_out, 'w') as f:
        for item in vcenter_list:
            f.write(f"{item['fqdn']}\n")
        print(f"File exported to {file_out}")


if __name__ == "__main__":
    main()
    
#################################################################################################
################################# END SCRIPT EXECUTION ##########################################