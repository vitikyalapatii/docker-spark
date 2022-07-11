# Copyright 2019 Splunk
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Prepare new files in a temporary base image
#
FROM registry.access.redhat.com/ubi8/ubi-minimal as package

ARG SPARK_URL=https://archive.apache.org/dist/spark/spark-2.3.0/spark-2.3.0-bin-hadoop2.7.tgz
ARG JDK_URL=https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u212-b04/OpenJDK8U-jre_x64_linux_hotspot_8u212b04.tar.gz

# install necessary tools
RUN microdnf update && microdnf install -y wget tar gzip

# download and install Spark
RUN wget -O /tmp/spark.tgz $SPARK_URL
RUN tar -C /tmp -zxvf /tmp/spark.tgz
RUN mkdir -p /opt/spark /opt/spark/eventlog
RUN mv /tmp/spark-*/* /opt/spark

# download and install JDK (JRE)
RUN wget -O /tmp/jdk.tgz $JDK_URL
RUN tar -C /tmp -zxvf /tmp/jdk.tgz
RUN mkdir -p /opt/jdk
RUN mv /tmp/jdk*-jre/* /opt/jdk

# add entrypoint and update permissions
ADD entrypoint.sh /opt/spark/entrypoint.sh
ADD setenv.sh /opt/spark/setenv.sh
RUN chmod a+x /opt/spark/entrypoint.sh /opt/spark/setenv.sh
RUN chmod -R a+r /opt/spark


#
# Create final image
#
FROM registry.access.redhat.com/ubi8/ubi-minimal
LABEL name="splunk" \
      maintainer="support@splunk.com" \
      vendor="splunk" \
      version="0.0.2" \
      release="1" \
      summary="Spark image for Splunk DFS" \
      description="Custom image that includes JRE and Spark"

# setup environment variables
ENV JAVA_HOME=/opt/jdk
ENV SPARK_HOME=/opt/spark
ENV SPARK_MASTER_HOSTNAME=127.0.0.1
ENV SPARK_MASTER_PORT=7777
ENV SPARK_WORKER_PORT=7777
ENV SPARK_MASTER_WEBUI_PORT=8009
ENV SPARK_WORKER_WEBUI_PORT=7000
ENV PATH=$PATH:/opt/jdk/bin:/opt/spark/bin
ENV DEBIAN_FRONTEND=noninteractive
ENV SPLUNK_HOME=/opt/splunk \
    SPLUNK_GROUP=splunk \
    SPLUNK_USER=splunk

# Currently kubernetes only accepts UID and not USER field to
# start a container as a particular user. So we create Splunk
# user with pre-determined UID.
ARG UID=41812
ARG GID=41812

# add splunk user and group
RUN mkdir /licenses \
    && curl -o /licenses/apache-2.0.txt https://www.apache.org/licenses/LICENSE-2.0.txt \
    && curl -o /licenses/EULA_Red_Hat_Universal_Base_Image_English_20190422.pdf https://www.redhat.com/licenses/EULA_Red_Hat_Universal_Base_Image_English_20190422.pdf \
    && mkdir -p /run/user/$(id -u `whoami`) \
    && microdnf update && microdnf install -y --nodocs shadow-utils hostname \
    && groupadd -r -g ${GID} ${SPLUNK_GROUP} \
    && useradd -r -m -u ${UID} -g ${GID} -s /sbin/nologin -d ${SPLUNK_HOME} ${SPLUNK_USER} \
    && mkdir -p /mnt/jdk /mnt/spark \
    && chown -R splunk.splunk ${SPLUNK_HOME} /mnt/jdk /mnt/spark

# copy package files
COPY --from=package --chown=splunk:splunk /opt /opt

# run as user splunk
USER ${SPLUNK_USER}
WORKDIR ${SPLUNK_HOME}

ENTRYPOINT /opt/spark/entrypoint.sh
