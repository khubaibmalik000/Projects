# CI/CD Pipeline: GitLab + Jenkins + SonarQube

A step-by-step runbook for wiring up a CI/CD pipeline where GitLab triggers Jenkins builds via webhook, and SonarQube gates deployments on code quality (bugs, vulnerabilities, code smells, duplication).

---



====================================Create Account on gitlab then integrate the remote repository with local git=========================================
       Place all the files including the Jenkins file inside you local repository
       For my project as it was a static website of HTML CSS so I placed Jenkins file in the       same folder
#Git add .
#Git commit -m  “Message”
#Git push origin main

================================================== Install Jenkins on machine ============================================================================

Update your system
#sudo apt update
#sudo apt upgrade -y
________________________________________

Install Java (required for Jenkins)
#sudo apt install openjdk-17-jdk -y
#java -version
Jenkins 2.401+ works best with Java 17.
________________________________________
 Add Jenkins repository and key
#curl -fsSL https://pkg.jenkins.io/debian/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

#echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
________________________________________
Install Jenkins
#sudo apt update
#sudo apt install jenkins -y
________________________________________
Start and enable Jenkins service
#sudo systemctl start jenkins
#sudo systemctl enable jenkins
#sudo systemctl status jenkins
Status should show active (running).
________________________________________
 Open Jenkins in browser
•	URL: http://<your-server-ip>:8080
•	Get initial admin password:

#sudo cat /var/lib/jenkins/secrets/initialAdminPassword
•	Use this password to unlock Jenkins and install suggested plugins.


======================================================= Install SonarQube ==========================================================
Install Java
#sudo apt update
#sudo apt install openjdk-17-jdk -y
#java -version
________________________________________
Download & unzip SonarQube
#cd /opt
#sudo wget https://binaries.sonarsource.com/CommercialDistribution/sonarqube/sonarqube-10.5.0.74707.zip
#sudo apt install unzip -y
#sudo unzip sonarqube-10.5.0.74707.zip
#sudo mv sonarqube-10.5.0.74707 sonarqube
#sudo chown -R $USER:$USER sonarqube
________________________________________
Start SonarQube (uses embedded H2 DB)
#cd /opt/sonarqube/bin/linux-x86-64
#./sonar.sh start
           Access: http://<server-ip>:9000
           Default login: admin/admin


=====================================================Integrate SonarQube with Jenkins=========================================================

    Install SonarQube Plugin in Jenkins
1.	Go to Jenkins → Manage Jenkins → Manage Plugins → Available.
2.	Search for “SonarQube Scanner”.
3.	Install it and restart Jenkins if needed.
________________________________________
Configure SonarQube Server in Jenkins
1.	Go to Jenkins → Manage Jenkins → Configure System → SonarQube Servers → Add SonarQube.
2.	Fill in:
o	Name: SonarQube (any name)
o	Server URL: http://<server-ip>:9000
o	Server authentication token: Generate token in SonarQube → My Account → Security → Generate Token
3.	Save.
________________________________________
 Configure SonarQube Scanner
1.	Go to Jenkins → Manage Jenkins → Global Tool Configuration → SonarQube Scanner → Add SonarQube Scanner.
2.	Select Install automatically or point to the scanner path (/opt/sonar-scanner/bin).
3.	Save.

==================================================Integrate GitLab with Jenkins======================================================

Create an SSH Key for Jenkins
On your Jenkins server (or wherever Jenkins runs):
#ssh-keygen -t rsa -b 4096 -C "jenkins@gitlab" -f ~/.ssh/jenkins_rsa_gitlab
•	Leave passphrase empty.
•	This creates:
o	~/.ssh/jenkins_rsa_gitlab → private key
o	~/.ssh/jenkins_rsa_gitlab.pub → public key
________________________________________
 Add SSH Public Key to GitLab
1.	Go to GitLab → Your Project → Settings → Repository → Deploy Keys
2.	Click Add Deploy Key
3.	Paste contents of jenkins_rsa_gitlab.pub
4.	Give a name (e.g., Jenkins) and check Allow write access
5.	Save
________________________________________
 Add SSH Private Key to Jenkins
1.	Jenkins → Manage Jenkins → Credentials → System → Global credentials → Add Credentials
2.	Kind: SSH Username with private key
o	Username: git
o	Private Key: Enter directly → paste contents of ~/.ssh/jenkins_rsa_gitlab
3.	Give an ID (e.g., gitlab-ssh-key)
________________________________________
 Test GitLab Connection
•	On Jenkins server:
#ssh -T git@gitlab.com
•	Should say: Welcome to GitLab, @username!

============================================================== Install GitLab Plugin =======================================================

1.	Jenkins → Manage Jenkins → Manage Plugins → Available
2.	Search: GitLab Plugin
3.	Install and restart Jenkins if required
________________________________________
 Add GitLab Server Connection
1.	Jenkins → Manage Jenkins → Configure System
2.	Scroll to GitLab section → Click Add GitLab Server
Settings to fill:
•	Name: GitLab-Connection (any name)
•	API URL: https://gitlab.com (or your self-hosted GitLab URL)
•	Credentials: Add → GitLab API Token
o	Go to GitLab → User Settings → Access Tokens → Create token with api scope
o	Paste token here
•	Test Connection: Click → should return success
To build a job with webhook in GitLab there are two ways to build job of pipeline of Jenkins either click trigger build remotely or other way is with plugin in Trigger Section of configure pipeline select Build when a change is pushed to GitLab. GitLab webhook in production we must automate things that’s why we will first set GitLab plugin then we will select build when a change is pushed to Gitlab webhook.

=========================================================== Build Jenkins Pipeline ================================================================

Configure the Jenkins Pipeline Job
General
•	Description: Pipeline for deployment with SonarQube analysis
•	Discard old builds:  optional
•	Do not allow concurrent builds:  optional
•	Abort previous builds:  optional
•	GitLab Project / Connection: Select your GitLab connection
________________________________________
Build Triggers
•	Check Build when a change is pushed to GitLab
o	This enables the webhook
•	Optional: select Push Events, Merge Request Events as triggers
________________________________________
Pipeline Section
•	Definition: Pipeline script from SCM
•	SCM: Git
•	Repository URL: git@gitlab.com:username/repo.git
•	Credentials: select Jenkins SSH key for GitLab
•	Branches to build: */main
•	Script Path: Jenkinsfile
•	Lightweight checkout: 
Leave other fields default unless needed
________________________________________

 Configure GitLab Webhook
1.	In GitLab → Project → Settings → Webhooks
2.	URL: Jenkins webhook URL from job:
http://<jenkins-server-ip>:8080/project/<job-name>
3.	Triggers:
•	 Push events
•	 Merge Request events (optional)
4.	Optional: Enable SSL verification if using HTTPS
5.	Click Add Webhook
________________________________________
 Test Webhook
•	In GitLab Webhooks → Click Test → choose Push events
•	Response should be 200 OK → means Jenkins received the event
________________________________________
 Save & Build
1.	Click Save in Jenkins job
2.	Build Now → Jenkins will:
o	Pull code from GitLab
o	Execute the Jenkinsfile pipeline
o	Trigger SonarQube analysis if configured

================================================== Code smelling from SonarQube ==============================================================

Now we will make code smell section if new code which is pushed to GitLab has some bugs then SonarQube quality gate will look after if it meets its threshold  condition for quality gate of the SonarQube then the deployment will stop and pipeline will stop.
Configure Webhook for Jenkins
1.	Log in to SonarQube.
2.	Go to your project:
3.	Projects → [Your Project] → Project Settings → Webhooks
4.	Click Create.
5.	Fill in the fields:
o	Name: jenkins-quality-gate

o	URL:
o	http://<JENKINS_IP>:8080/sonarqube-webhook/
Replace <JENKINS_IP> with your Jenkins server IP.
o	Has Secret? → leave unchecked.
6.	Click Create.
7.	After creation, it will appear in the list. At first, Last delivery will say “Never”, which is normal until an analysis runs successfully.

Configure Quality Gate for the Project
1.	In your project, go to:
2.	Project Settings → Quality Gate
3.	Click Change (or Select a Quality Gate)
4.	Either create a new Quality Gate or select an existing one:
o	To create a new one:
	Go to Quality Gates → Create
	Name it something like: Hotel-Web-App-Gate
	Add rules, for example:

Metric	Condition	Value
Bugs	is greater than	0
Vulnerabilities	is greater than	0
Code Smells	is greater than	5
Duplicated Lines (%)	is greater than	3
Security Hotspots Reviewed	is less than	100%
		
5.	Save the Quality Gate.
6.	Go back to your project → Project Settings → Quality Gate → Assign the gate you just created.
Now your project is linked to that Quality Gate.
                                                                                     
