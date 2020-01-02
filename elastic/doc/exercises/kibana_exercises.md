<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Create a Visualisation based on a search in Discover](#create-a-visualisation-based-on-a-search-in-discover)
- [Get percentiles of x requests](#get-percentiles-of-x-requests)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->


# Create a Visualisation based on a search in Discover

# Get percentiles of x requests

# get number of requests from every ip address

Useful for:
- searching for DoS type of behavior

answer:
- Visualization
- data table
- metric: count
- buckets: split rows -> Terms -> json.remote_ip.keyword   (keyword because you want to use an Elastic field that hasn't been split into separate tokens)

# Get time spent in gRPC calls

Useful for:
- analyzing which method runs the most often
