provider "aws" {
  region = "ap-south-1"
  profile = "mkprofile"
}







//creating key-pair

resource "tls_private_key" "this"{
  algorithm="RSA"
}

resource "local_file" "private_key"{
  //this block is for downloading the pem file of keypair.
  content=tls_private_key.this.private_key_pem
  filename="terrakey.pem"
}

resource "aws_key_pair" "key" {
  key_name   = "mkkey"
  public_key = tls_private_key.this.public_key_openssh
}












//creating security group

resource "aws_security_group" "firewall" {
  name        = "firewall"
  description = "Allow SSH AND HTTP for webhosting"


  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [ "0.0.0.0/0" ]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "firewall"
  }
}

output "firewallinfo"{
  value=aws_security_group.firewall.tags.Name
}

output "keyname"{
  value=aws_key_pair.key.key_name
}


//variable for the key name 
variable "key"{
  type =string
  default="mkkey"
}


//variable for the security group name which support port 22,80.
variable "securityname"{
  type=string
  default="firewall"
}












//creating instance
resource "aws_instance" "myin" {
  
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name = aws_key_pair.key.key_name
  security_groups=[aws_security_group.firewall.tags.Name]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.this.private_key_pem
    host     = aws_instance.myin.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd ",
      "sudo systemctl enable httpd"
     ]
   }
  tags = {
    Name = "mkos1"
  }
}


//information about the launched instance
output "instanceinfo"{
  value=aws_instance.myin
}










//creating ebs volume of 1 gib with the availability_Zone of the launched instance
resource "aws_ebs_volume" "ebs" {
  availability_zone = aws_instance.myin.availability_zone
  size              = 1

  tags = {
    Name = "terraebs"
  }
}


//information about the ebs volume
output "ebsinfo"{
  value=aws_ebs_volume.ebs
}


//This is for attaching the created ebs volume with the launched instance
resource "aws_volume_attachment" "ebs_att" {
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.ebs.id}"
  instance_id = "${aws_instance.myin.id}"
  force_detach=true
}


//information of attaching the volume
output "volume_attachment_info"{
  value=aws_volume_attachment.ebs_att
}







//this is for creating the bucket 
resource "aws_s3_bucket" "bucket"{
  bucket ="baltttibanao"
  acl ="public-read"
  region="ap-south-1"
  
 //this is for downloading the image from the github to local system .from there it will be copy to the bucket.
  provisioner "local-exec" {
        command =  "git clone https://github.com/Minshu123/terratask1.git " 
   }

  provisioner "local-exec"{
    	when=destroy
	command="echo y | rmdir /s terratask1"
  }
  tags={
     Name="mkkbaltibanao"
  }
  
  versioning{
	enabled=true
  }
}


//this gives the information about the bucket log.
output "bucketinfo"{
  value="${aws_s3_bucket.bucket}"
}

resource "aws_s3_bucket_object" "bucketobject"{
  bucket ="${aws_s3_bucket.bucket.id}"
  key="shiv.jpg"
  source="terratask1/shiv.jpg"
  acl="public-read"
}


//this gives the information about the bucket object log .
output "bucketobjectinfo"{
  value="${aws_s3_bucket_object.bucketobject}"
}



locals {
    s3_origin_id = "S3-${aws_s3_bucket.bucket.bucket}"
}


//creating the cloud front
resource "aws_cloudfront_distribution" "cldfront" {
    default_cache_behavior {
        allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
        cached_methods   = ["GET", "HEAD"]
        target_origin_id = local.s3_origin_id
        forwarded_values {
            query_string = false
            cookies {
                forward = "none"
            }
        }
        viewer_protocol_policy = "allow-all"
    }

  enabled             = true

  origin {
        domain_name = aws_s3_bucket.bucket.bucket_domain_name
        origin_id   = local.s3_origin_id
    }


  restrictions {
        geo_restriction {
        restriction_type = "none"
        }
    }


   viewer_certificate {
        cloudfront_default_certificate = true
    }


  connection {
        type    = "ssh"
        user    = "ec2-user"
        host    = aws_instance.myin.public_ip
        port    = 22
        private_key = tls_private_key.this.private_key_pem
    }


  provisioner "remote-exec" {
        inline  = [
            "sudo su << EOF",
            "echo \"<img src=\"http://${self.domain_name}/${aws_s3_bucket_object.bucketobject.key}\" height=625 width=1350>\" >> /var/www/html/index.html",
            "EOF"
        ]
    }
}

//for automatic brouwsing 
resource "null_resource" "result"{
  depends_on=[
    aws_instance.myin,null_resource.remoteaccess,aws_cloudfront_distribution.cldfront
  ]

  provisioner "local-exec"{
	command="start chrome ${aws_instance.myin.public_ip}/index.html"
  }
}




//Establishing connection with the instance os using ssh .
resource "null_resource" "remoteaccess"  {

//this depends block only run if attachment to the volume with is completed.
 depends_on = [
    aws_volume_attachment.ebs_att
  ]


  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = tls_private_key.this.private_key_pem
    host     = aws_instance.myin.public_ip
  }

 provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/Minshu123/terratask1.git /var/www/html/"
    ]
  }
}
